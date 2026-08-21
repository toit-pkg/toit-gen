// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Library to create Toit code.

It provides an Object-Oriented AST (Abstract Syntax Tree) to build Toit
programs programmatically, managing names properly to prevent collisions, 
and ultimately writing the generated code to files or returning it as strings.

A $Program contains one or multiple $Library instances. Variables, functions, 
classes, and parameters are defined as $RefTarget instances. Code relies on
$Expression and $Statement subclasses to build logic blocks.

See the `examples` directory for examples.
*/

import fs
import io
import host.directory
import host.file

import .namer show GlobalNamer MemberNamer LocalNamer Namer
import .visitor show NodeVisitor
import .generator_ show *
import .validator_ show validate-program_

next-hash-code_ := 0

interface Node:
  hash-code -> int
  operator == other/any -> bool
  accept visitor/NodeVisitor -> any

abstract class BaseNode_ implements Node:
  hash-code/int ::= next-hash-code_++
  abstract accept visitor/NodeVisitor -> any
  operator == other/any -> bool:
    return identical this other

/**
A structured description of an invalid or unsupported AST shape.

The $code is stable and suitable for programmatic handling. The $message is
  intended for humans, while $library-path and $node identify the affected
  part of the generated program.
*/
class ValidationDiagnostic:
  code/string
  message/string
  library-path/string?
  node/Node

  constructor .code .message .node --.library-path=null:

  stringify -> string:
    location := library-path ? " in '$(library-path)'" : ""
    return "$(code)$(location): $(message)"

/**
Thrown by $Program.gen when validation finds one or more diagnostics.
*/
class ValidationError:
  diagnostics/List  // Of ValidationDiagnostic.

  constructor .diagnostics:

  stringify -> string:
    lines := diagnostics.map: "  $it"
    return "Invalid toit-gen AST:\n$(lines.join "\n")"

/**
A reference to a named element for use within Toitdocs.
*/
class ToitdocNameRef:
  holder/RefTarget?
  target/RefTarget

  constructor .target --.holder=null:

/**
A reference to a specific function or method with matching parameters for use within Toitdocs.
*/
class ToitdocExactRef:
  holder/RefTarget?
  target/Function

  constructor .target --.holder=null:

/**
A reference to the superclass for use within Toitdocs.
*/
class ToitdocSuperRef:

/**
A full Toit program.
*/
class Program extends BaseNode_:
  libraries/List ::= []

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Program this

  assign-names_ -> none:
    namers := {:}
    // Phase 1: Reserve fixed (pre-assigned) names.
    this.accept (FixedNamingVisitor namers)

    // Phase 2: Assign class and global variable names.
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      library.classes.do: | cls/Class |
        if not cls.name:
          cls.name = global-namer.use-class cls.preferred-name --private=cls.is-private
      library.globals.do: | g/VarDefinition |
        if not g.name:
          g.name = global-namer.use-global g.preferred-name --private=g.is-private

    // Phase 3: Assign function names, field names, and static field names.
    // Uses shared naming so that overloaded functions and fields with
    // the same preferred name get the same assigned name.
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      global-cache := {:}
      library.functions.do: | fun/Function |
        if not fun.name:
          fun.name = global-namer.use-shared-global fun.preferred-name --private=fun.is-private --cache=global-cache
      library.classes.do: | cls/Class |
        member-namer/MemberNamer := namers[cls]
        member-cache := {:}
        cls.members.do: | fun/Function |
          if not fun.name:
            fun.name = member-namer.use-shared-member fun.preferred-name --private=fun.is-private --cache=member-cache
        cls.static-functions.do: | fun/Function |
          if not fun.name:
            fun.name = member-namer.use-shared-member fun.preferred-name --private=fun.is-private --cache=member-cache
        cls.fields.do: | field/VarDefinition |
          if not field.name:
            field.name = member-namer.use-shared-member field.preferred-name --private=field.is-private --cache=member-cache
        cls.static-fields.do: | field/VarDefinition |
          if not field.name:
            field.name = member-namer.use-shared-member field.preferred-name --private=field.is-private --cache=member-cache

    // Phase 4: Assign named parameter names.
    // Uses shared naming so overloaded functions with the same named
    // parameter get the same assigned parameter name.
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      global-param-cache := {:}
      library.functions.do: | fun/Function |
        fun.parameters.do: | param/VarDefinition |
          if not param.name and param.is-named and not param.initializes-field:
            param.name = global-namer.use-shared-global param.preferred-name --cache=global-param-cache
      library.classes.do: | cls/Class |
        member-namer/MemberNamer := namers[cls]
        member-param-cache := {:}
        cls.members.do: | fun/Function |
          fun.parameters.do: | param/VarDefinition |
            if not param.name and param.is-named and not param.initializes-field:
              param.name = member-namer.use-shared-member param.preferred-name --cache=member-param-cache
        cls.static-functions.do: | fun/Function |
          fun.parameters.do: | param/VarDefinition |
            if not param.name and param.is-named:
              param.name = member-namer.use-shared-member param.preferred-name --cache=member-param-cache

    // Phase 5: Assign unnamed, non-block parameter names.
    this.accept (UnnamedParamNamingVisitor namers)

    // Phase 6: Assign prefixes and remaining local names.
    // Collect all already-assigned names to ensure prefixes don't
    // clash with any name in any scope.
    all-names := {}
    namers.do: | _ curr-namer/Namer |
      all-names.add-all curr-namer.used-names
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      library.imports.do: | imp/Import |
        if imp.preferred-prefix:
          imp.prefix = global-namer.use-prefix imp.preferred-prefix
              --also-avoid=all-names
    this.accept (LocalNamingVisitor namers)

  /**
  Validates this program without assigning names or rendering source.

  Returns all diagnostics found in one traversal. An empty list means the AST
    is supported and internally consistent.
  */
  validate -> List:
    return validate-program_ this

  validate-or-throw_ -> none:
    diagnostics := validate
    if not diagnostics.is-empty: throw (ValidationError diagnostics)

  /**
  Generates the Toit code for the program and saves it to the file system.
  */
  gen -> none:
    generated := gen --in-memory
    generated.do: | path/string code/string |
      write-generated-file_ path code

  write-generated-file_ path/string code/string -> none:
    dir := fs.dirname path
    if not file.is-directory dir:
      if file.is-file dir:
        throw "Cannot create directory $dir: A file with that name exists."
      directory.mkdir --recursive dir

    permissions/int? := null
    target-stat := file.stat path
    if target-stat and target-stat[file.ST-TYPE] == file.REGULAR-FILE:
      permissions = target-stat[file.ST-MODE]

    temp-dir := directory.mkdtemp (fs.join dir ".toit-gen-")
    temp-path := fs.join temp-dir "output"
    try:
      stream := file.Stream.for-write temp-path
      try:
        stream.out.write code
      finally:
        stream.close
      if permissions: file.chmod temp-path permissions
      file.rename temp-path path
    finally:
      directory.rmdir temp-dir --recursive --force

  /**
  Generates the Toit code for the program and returns it as a map from path to content.
  */
  gen --in-memory/True -> Map:
    validate-or-throw_
    assign-names_
    result := {:}
    libraries.do: | library/Library |
      buffer := io.Buffer
      context := WriteContext_ buffer
      library.gen_ context
      code := buffer.to-string
      result[library.path] = code
    return result



/**
A Toit library.
*/
class Library extends BaseNode_:
  path/string
  imports/List ::= []  // Of Import.
  exports/List ::= []  // Of Export.
  statics/List ::= []
  classes/List ::= []  // Of Class.
  globals/List ::= []  // Of VarDefinition.
  functions/List ::= []  // Of Function.
  toitdoc/List? := null

  constructor .path:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Library this

  gen_ context/WriteContext_ -> none:
    visitor := GeneratingVisitor context
    visitor.visit-Library this

  /**
  Creates an $Import for $package, adds it to this library, and returns it.

  $module is an optional dot-separated submodule path within the package,
    e.g. `"client"` for `import http.client`. If null, the import targets
    the package's main module (`import http`).

  The import's $Import.preferred-prefix defaults to $preferred-prefix when
    given, otherwise to the last segment of the resolved path — so
    `add-import http-pkg` (with `http-pkg.prefix == "http"`) yields a prefix
    of `"http"` and renders as `import http`. The redundant
    `import http as http` form is suppressed by the renderer.

  The resulting $Import retains a reference to $package via $Import.package
    so downstream tooling (e.g. `package.yaml` emitters) can recover the
    package id.
  */
  add-import package/Package
      --module/string?=null
      --preferred-prefix/string?=null
      --show-all/bool=false -> Import:
    segments := [package.prefix]
    if module: segments.add-all (module.split ".")
    prefix := preferred-prefix or segments.last
    imp := Import segments
        --preferred-prefix=prefix
        --package=package
        --show-all=show-all
    imports.add imp
    return imp

  /**
  Creates a relative $Import for $path, adds it to this library, and
    returns it.

  $path is a dot-separated chain of segments without the leading dot, so
    `add-relative-import "openapi"` renders as `import .openapi`.

  Unlike package imports, a relative import binds no implicit prefix, so its
    references are brought into scope directly (`import .openapi` exposes the
    bare names). Pass $preferred-prefix to render an explicit `as` clause
    (`import .openapi as oa`) and qualify the references through it.
  */
  add-relative-import path/string
      --preferred-prefix/string?=null
      --show-all/bool=false -> Import:
    imp := Import (path.split ".")
        --preferred-prefix=preferred-prefix
        --is-relative
        --show-all=show-all
    imports.add imp
    return imp

  /**
  Creates an always-prefixed import of the SDK's `core` module.

  References created through the returned $Import remain qualified, so a
    generated declaration named `Map`, `List`, or another core type cannot
    change what those references resolve to.
  */
  add-core-import -> Import:
    imp := Import ["core"] --preferred-prefix="core"
    imports.add imp
    return imp

  /**
  Creates a $Class with $preferred-name, adds it to this library, and returns it.
  */
  add-class preferred-name/string
      --kind/int=Class.CLASS
      --is-abstract/bool=false
      --is-private/bool=false
      --super-class/Ref?=null -> Class:
    cls := Class preferred-name
        --kind=kind
        --is-abstract=is-abstract
        --is-private=is-private
        --super-class=super-class
    classes.add cls
    return cls

  /**
  Creates a $Function with $preferred-name, adds it to this library's
    top-level functions, and returns it.
  */
  add-function preferred-name/string
      --parameters/List
      --return-type/Ref?=null
      --is-abstract/bool=false
      --is-private/bool=false
      body/Statement?=null -> Function:
    fn := Function preferred-name
        --parameters=parameters
        --return-type=return-type
        --is-abstract=is-abstract
        --is-private=is-private
        body
    functions.add fn
    return fn

/**
A Toit package referenced by one or more $Import declarations.

Carries the package's identity ($id) — typically a URL like
  `github.com/toitware/pkg-http` — alongside the $prefix as declared in
  `package.yaml`. The $prefix is also the first segment of import paths
  for this package.

For modules that ship with the SDK and don't have a package id (e.g.
  `core`, `net`), use $Package.sdk.
*/
class Package:
  /**
  The package id, typically a URL like `github.com/toitware/pkg-http`.

  null for packages bundled with the SDK.
  */
  id/string?
  /**
  The prefix as declared in `package.yaml` and used as the first segment
    of import paths for this package.
  */
  prefix/string

  constructor --.prefix --.id:

  /**
  Constructs a $Package for an SDK-bundled module — one that has no
    package id and is imported by its bare $prefix.
  */
  constructor.sdk --.prefix:
    id = null

  /// Whether this package is bundled with the SDK (no $id).
  is-sdk -> bool:
    return id == null

/**
An import declaration.
*/
class Import extends BaseNode_:
  is-relative/bool
  segments/List  // Of string.
  preferred-prefix/string? := null
  prefix/string? := null
  show-all/bool
  /**
  The owning $Package, if any.

  null for relative imports and for $Import instances built without a
    package (e.g. raw `core` imports).
  */
  package/Package? := null
  refs/List ::= []  // Of ImportedRef.

  constructor .segments
      --.preferred-prefix=null
      --.is-relative=false
      --.show-all=false
      --.package=null:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Import this

  is-core -> bool:
    return segments.size == 1 and segments[0] == "core"

  /**
  Whether references through this import are qualified with the $prefix
    (rendered as `prefix.name`) instead of brought into scope directly.

  A prefix is only usable when the rendered import actually binds one. A
    `show *` clause brings the names in unqualified and removes the prefix,
    so those imports are never qualified. A relative import binds a prefix
    only through an explicit `as`, which the renderer emits whenever $prefix
    is set.
  */
  uses-prefix -> bool:
    if show-all: return false
    return prefix != null

  /**
  Creates an $ImportedRef to $target through this import.
  */
  refer target/RefTarget -> ImportedRef:
    return ImportedRef this target

/**
An export declaration.
*/
class Export extends BaseNode_:
  exports/List ::= []  // Of Ref.

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Export this

/**
A Toit class, interface or mixin declaration.
*/
class Class extends BaseNode_ implements RefTarget:
  static CLASS ::= 0
  static INTERFACE ::= 1
  static MIXIN ::= 2

  kind/int
  preferred-name/string
  name/string? := null
  fields/List ::= []  // Of VarDefinition.
  members/List ::= []  // Of Function.
  static-fields/List ::= []
  static-functions/List ::= []
  is-abstract/bool := false
  is-private/bool := false
  super-class/Ref? := null
  interfaces/List ::= []  // Of Ref.
  mixins/List ::= []  // Of Ref.
  toitdoc/List? := null

  constructor .preferred-name --.is-abstract=false --.is-private=false --.kind --.super-class=null:

  /**
  A core class.

  Should only be used as a $RefTarget. As such, most of the fields don't matter.
  */
  constructor.core .name/string:
    kind = CLASS
    preferred-name = name
    is-abstract = false
    super-class = null

  /**
  A stub for a class imported from another package.

  Should only be used as a $RefTarget — typically combined with $Import.refer
    to produce a prefixed $ImportedRef. Like $Class.core, this constructor
    fixes the rendered $name and skips the naming phase, since the class
    isn't part of the generated output.
  */
  constructor.imported .name/string:
    kind = CLASS
    preferred-name = name
    is-abstract = false
    super-class = null

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Class this

  /**
  Creates a $VarDefinition.field with $preferred-name, appends it to this
    class's $fields, and returns it.
  */
  add-field preferred-name/string
      --type/Ref?=null
      --is-nullable/bool=false
      --is-final/bool=true
      --is-private/bool=false
      --initial/Expression?=null -> VarDefinition:
    field := VarDefinition.field preferred-name
        --type=type
        --is-nullable=is-nullable
        --is-final=is-final
        --is-private=is-private
        --initial=initial
    fields.add field
    return field

  /**
  Creates a $Function with $preferred-name, appends it to this class's
    $members, and returns it.
  */
  add-method preferred-name/string
      --parameters/List
      --return-type/Ref?=null
      --is-abstract/bool=false
      --is-private/bool=false
      body/Statement?=null -> Function:
    fn := Function preferred-name
        --parameters=parameters
        --return-type=return-type
        --is-abstract=is-abstract
        --is-private=is-private
        body
    members.add fn
    return fn

  /**
  Creates a constructor, appends it to this class's $members, and returns it.

  Without a $name the constructor is unnamed (`constructor`); with a $name it
    is a named constructor (`constructor.$name`).
  */
  add-constructor --name/string?=null --parameters/List=[] body/Statement?=null -> Function:
    constr := Function.constr --name=name --parameters=parameters body
    members.add constr
    return constr

/**
A Toit function or method.
*/
class Function extends BaseNode_ implements RefTarget:
  preferred-name/string
  name/string? := null
  parameters/List ::= []  // Of VarDefinition.
  return-type/Ref?
  body/Statement? := null
  is-abstract/bool
  is-private/bool
  is-constructor/bool := false
  toitdoc/List? := null

  constructor .preferred-name
      --.parameters
      --.return-type
      --.is-abstract=false
      --.is-private=false
      .body=null:

  constructor.constr --.parameters --name/string?=null .body=null:
    if not name:
      preferred-name = "constructor"
      this.name = "constructor"
    else:
      preferred-name = name
    is-abstract = false
    is-private = false
    return-type = null
    is-constructor = true

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Function this

/**
A Toit operator.
*/
class Operator extends Function:
  operator-string/string

  constructor .operator-string --parameters/List --return-type/Ref?=null --is-abstract/bool=false body/Statement?:
    op-name := "operator $operator-string"
    super op-name
        --parameters=parameters
        --return-type=return-type
        --is-abstract=is-abstract
        body

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Operator this

/**
A variable, parameter or field definition.
*/
class VarDefinition extends BaseNode_ implements RefTarget:
  preferred-name/string
  name/string? := null
  type/Ref?
  initial/Expression?
  is-nullable/bool  // Only used if $type is not null.
  is-block/bool
  is-named/bool
  is-final/bool
  is-private/bool
  initializes-field/VarDefinition? := null
  toitdoc/List? := null

  constructor.parameter .preferred-name
      --.type=null
      --.initial=null
      --.is-block=false
      --.is-named=false
      --.is-nullable=false
      --.is-final=false
      --.is-private=false:

  /** Creates a constructor parameter that initializes $field directly. */
  constructor.field-parameter field/VarDefinition
      --.initial=null
      --.is-named=false:
    initializes-field = field
    preferred-name = field.preferred-name
    type = field.type
    is-nullable = field.is-nullable
    is-block = false
    is-final = false
    is-private = false

  constructor.ignored:
    preferred-name = "_"
    name = "_"
    is-block = false
    is-named = false
    is-nullable = false
    initial = null
    type = null
    is-final = false
    is-private = false

  constructor.it:
    preferred-name = "it"
    name = "it"
    is-block = false
    is-named = false
    is-nullable = false
    initial = null
    type = null
    is-final = false
    is-private = false

  constructor.local .preferred-name
      --.type=null
      --.is-nullable=false
      --.is-final=false
      --.is-private=false
      --.initial/Expression:
    is-block = false
    is-named = false

  constructor.field .preferred-name
      --.type=null
      --.is-nullable=false
      --.is-final=true
      --.is-private=false
      --.initial/Expression?:
    is-block = false
    is-named = false

  accept visitor/NodeVisitor -> any:
    return visitor.visit-VarDefinition this

/**
A Toit statement.

Strictly speaking, Toit doesn't have the distinction between
  statements and expressions.
In practice, however, some constructs clearly are only used in
  statement-like positions.
*/
abstract class Statement extends BaseNode_:
  constructor expr/Expression:
    return ExpressionStatement expr

  constructor:

  abstract accept visitor/NodeVisitor -> any

/**
A sequence of statements.
*/
class Sequence extends Statement:
  statements/List ::= []  // Of Statement.

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Sequence this

  add node/Node -> none:
    if node is Statement:
      statements.add (node as Statement)
    else:
      statements.add (Statement (node as Expression))

  /**
  Defines a new local variable.
  */
  define preferred-name/string -> VarDefinition
      --type/Ref?=null
      initial/Expression:
    definition := VarDefinition.local preferred-name
        --initial=initial
        --type=type
    add (Statement (LocalDefinition definition))
    return definition

  /** Calls $target. */
  call target/Expression -> none:
    call target --arguments=[]

  /** Calls $target with one argument. */
  call target/Expression arg0/Expression -> none:
    call target --arguments=[arg0]

  /** Calls $target with two arguments. */
  call target/Expression arg0/Expression arg1/Expression -> none:
    call target --arguments=[arg0, arg1]

  /** Calls $target with multiple $arguments. */
  call target/Expression --arguments/List -> none:
    expr := Call target --arguments=arguments
    add (Statement expr)

  /**
  Adds a method-call statement: `$target.$method-name $arguments...`.
  */
  invoke target/Expression method-name/string --arguments/List=[] -> none:
    expr := Call target method-name --arguments=arguments
    add (Statement expr)

  /** Adds an if statement. */
  iff condition/Expression then-branch/Statement else-branch/Statement?=null -> none:
    if-statement := If condition then-branch else-branch
    add if-statement

  /** Adds a return statement. */
  ret value/Expression?=null -> none:
    return-statement := Return value
    add return-statement

  /** Adds an assignment statement. */
  assign target/Ref value/Expression -> none:
    assign := Assign target value
    add (Statement assign)

  /** Adds a while loop. */
  whle condition/Expression body/Statement -> none:
    add (While condition body)

  /** Adds a break statement. */
  brk value/Expression?=null -> none:
    add (Break value)

  /** Adds a continue statement. */
  cont -> none:
    add (Continue)

  /** Adds a try-finally statement. */
  try-finally body/Statement handler/Statement -> none:
    add (TryFinally body handler)

/**
An if statement.
*/
class If extends Statement:
  condition/Expression
  then-branch/Statement
  else-branch/Statement? := null

  constructor .condition .then-branch .else-branch=null:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-If this

/**
A return statement.
*/
class Return extends Statement:
  value/Expression? := null

  constructor .value=null:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Return this

/**
A statement that merely evaluates an expression (and discards its result).
*/
class ExpressionStatement extends Statement:
  expression/Expression

  constructor .expression:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-ExpressionStatement this

/**
A statement that defines a local variable.
*/
class LocalDefinition extends Expression:
  definition/VarDefinition

  constructor .definition:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-LocalDefinition this

/**
A break statement.
*/
class Break extends Statement:
  value/Expression? := null

  constructor .value=null:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Break this

/**
A continue statement.
*/
class Continue extends Statement:
  constructor:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Continue this

/**
A while loop statement.
*/
class While extends Statement:
  condition/Expression
  body/Statement

  constructor .condition .body:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-While this

/**
A for loop statement.
*/
class For extends Statement:
  init/Expression
  condition/Expression
  update/Expression
  body/Statement

  constructor .init .condition .update .body:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-For this

/**
A try-finally statement.
*/
class TryFinally extends Statement:
  body/Statement
  handler/Statement

  constructor .body .handler:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-TryFinally this

/**
A throw statement.
*/
class Throw extends Statement:
  value/Expression

  constructor .value:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Throw this


/**
A Toit expression.
*/
abstract class Expression extends BaseNode_:
  abstract accept visitor/NodeVisitor -> any

/**
A function or method call.
*/
class Call extends Expression:
  target/Expression
  method-name/string? := null
  arguments/List  // Of Expression.

  constructor .target .method-name=null --.arguments=[]:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Call this

/**
An index operation (e.g. `foo[bar]`).
*/
class Index extends Expression:
  target/Expression
  index/Expression

  constructor .target .index:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Index this

/**
An indexed assignment (e.g. `foo[bar] = value`).
*/
class IndexAssign extends Expression:
  target/Expression
  index/Expression
  value/Expression

  constructor .target .index .value:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-IndexAssign this

/**
An assignment expression (e.g. `foo = bar`).
*/
class Assign extends Expression:
  target/Ref
  value/Expression

  constructor .target .value:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Assign this

/**
A block expression.
*/
class Block extends Expression:
  parameters/List  // Of VarDefinition.
  body/Statement

  constructor .body --.parameters=[]:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Block this

/**
A lambda expression.
*/
class Lambda extends Expression:
  parameters/List  // Of VarDefinition.
  body/Statement

  constructor .body --.parameters=[]:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Lambda this

/**
A literal value (string, int, float, bool, null, empty List or empty Map).
*/
class Literal extends Expression:
  value/any

  constructor .value:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Literal this

/**
A late initialization marker `?`.
*/
class LateInitialized extends Expression:
  accept visitor/NodeVisitor -> any:
    return visitor.visit-LateInitialized this

/**
A reference target, like a class, function, or variable.
*/
interface RefTarget:
  name -> string?

/**
A reference to a $RefTarget.

Refs are immutable and may be shared: the same $Ref instance may appear in
  multiple positions of the generated tree (for example as a field's type
  and as a getter's return type). An $ImportedRef must only be shared within
  the library whose $Import it references.
*/
class Ref extends Expression:
  target/RefTarget

  constructor .target:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Ref this

/**
A reference to an imported target.
*/
class ImportedRef extends Ref:
  imp/Import

  constructor .imp target/RefTarget:
    super target
    imp.refs.add this

  accept visitor/NodeVisitor -> any:
    return visitor.visit-ImportedRef this

/**
An `as` typecast expression.
*/
class As extends Expression:
  expression/Expression
  type/Ref

  constructor .expression .type:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-As this

/**
An `is` type check expression.
*/
class Is extends Expression:
  expression/Expression
  type/Ref

  constructor .expression .type:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Is this

/**
A binary operator expression.
*/
class Binary extends Expression:
  left/Expression
  op/string
  right/Expression

  constructor .left .op .right:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Binary this

/**
A ternary conditional expression `condition ? then-value : else-value`.
*/
class Ternary extends Expression:
  condition/Expression
  then-value/Expression
  else-value/Expression

  constructor .condition .then-value .else-value:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Ternary this

/**
A named argument.
*/
class Named extends Expression:
  parameter/VarDefinition
  value/Expression

  constructor .parameter .value:

  /**
  Creates a $Named for a call to a function that isn't generated by toit-gen.

  The callee's parameter $VarDefinition isn't available, so it is fabricated
    from $name. Use the regular constructor when calling a function that
    toit-gen generates and the parameter's $VarDefinition is in hand.
  */
  constructor.external name/string .value:
    parameter = VarDefinition.parameter name
    parameter.name = name

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Named this

/**
A unary operator expression.
*/
class Unary extends Expression:
  op/string
  operand/Expression

  constructor .op .operand:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Unary this

/**
A string interpolation expression.
*/
class StringInterpolation extends Expression:
  parts/List  // Alternating: string, Expression, string, ... Always odd length.

  constructor .parts:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-StringInterpolation this

/**
A list literal expression.
*/
class ListLiteral extends Expression:
  elements/List

  constructor .elements:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-ListLiteral this

/**
A map literal expression.
*/
class MapLiteral extends Expression:
  keys/List
  values/List

  constructor .keys .values:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-MapLiteral this

/**
A set literal expression.
*/
class SetLiteral extends Expression:
  elements/List

  constructor .elements:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-SetLiteral this

/**
An index slice expression (e.g. `foo[from..to]`).
*/
class IndexSlice extends Expression:
  target/Expression
  from/Expression?
  to/Expression?

  constructor .target --.from=null --.to=null:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-IndexSlice this

/**
A `super` expression.

In Toit, `super` calls the same-named method on the parent class.
When used with $Call, `super` becomes the target and the call's
  method-name generates `super.name args`.
*/
class Super extends Expression:
  accept visitor/NodeVisitor -> any:
    return visitor.visit-Super this
