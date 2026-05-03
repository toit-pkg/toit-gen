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
          cls.name = global-namer.use-class cls.preferred-name
      library.globals.do: | g/VarDefinition |
        if not g.name:
          g.name = global-namer.use-global g.preferred-name

    // Phase 3: Assign function names, field names, and static field names.
    // Uses shared naming so that overloaded functions and fields with
    // the same preferred name get the same assigned name.
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      global-cache := {:}
      library.functions.do: | fun/Function |
        if not fun.name:
          fun.name = global-namer.use-shared-global fun.preferred-name --cache=global-cache
      library.classes.do: | cls/Class |
        member-namer/MemberNamer := namers[cls]
        member-cache := {:}
        cls.members.do: | fun/Function |
          if not fun.name:
            fun.name = member-namer.use-shared-member fun.preferred-name --private=fun.is-static --cache=member-cache
        cls.static-functions.do: | fun/Function |
          if not fun.name:
            fun.name = member-namer.use-shared-member fun.preferred-name --private=fun.is-static --cache=member-cache
        cls.fields.do: | field/VarDefinition |
          if not field.name:
            field.name = member-namer.use-shared-member field.preferred-name --cache=member-cache
        cls.static-fields.do: | field/VarDefinition |
          if not field.name:
            field.name = member-namer.use-shared-member field.preferred-name --cache=member-cache

    // Phase 4: Assign named parameter names.
    // Uses shared naming so overloaded functions with the same named
    // parameter get the same assigned parameter name.
    libraries.do: | library/Library |
      global-namer/GlobalNamer := namers[library]
      global-param-cache := {:}
      library.functions.do: | fun/Function |
        fun.parameters.do: | param/VarDefinition |
          if not param.name and param.is-named:
            param.name = global-namer.use-shared-global param.preferred-name --cache=global-param-cache
      library.classes.do: | cls/Class |
        member-namer/MemberNamer := namers[cls]
        member-param-cache := {:}
        cls.members.do: | fun/Function |
          fun.parameters.do: | param/VarDefinition |
            if not param.name and param.is-named:
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
  Generates the Toit code for the program and saves it to the file system.
  */
  gen -> none:
    assign-names_
    libraries.do: | library/Library |
      path := library.path
      dir := fs.dirname path
      if not file.is-directory dir:
        if file.is-file dir:
          throw "Cannot create directory $dir: A file with that name exists."
        directory.mkdir --recursive dir
      stream := file.Stream.for-write path
      context := WriteContext_ stream.out
      library.gen_ context
      stream.close

  /**
  Generates the Toit code for the program and returns it as a map from path to content.
  */
  gen --in-memory/True -> Map:
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
An import declaration.
*/
class Import extends BaseNode_:
  is-relative/bool
  segments/List  // Of string.
  preferred-prefix/string? := null
  prefix/string? := null
  show-all/bool
  refs/List ::= []  // Of ImportedRef.

  constructor .segments
      --.preferred-prefix=null
      --.is-relative=false
      --.show-all=false:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Import this

  is-core -> bool:
    return segments.size == 1 and segments[0] == "core"

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
  super-class/Ref? := null
  interfaces/List ::= []  // Of Ref.
  mixins/List ::= []  // Of Ref.
  toitdoc/List? := null

  constructor .preferred-name --.is-abstract=false --.kind --.super-class=null:

  /**
  A core class.

  Should only be used as a $RefTarget. As such, most of the fields don't matter.
  */
  constructor.core .name/string:
    kind = CLASS
    preferred-name = name
    is-abstract = false
    super-class = null

  accept visitor/NodeVisitor -> any:
    return visitor.visit-Class this

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
  is-static/bool
  is-constructor/bool := false
  toitdoc/List? := null

  constructor .preferred-name
      --.parameters
      --.return-type
      --.is-abstract=false
      --.is-static=false
      .body=null:

  constructor.constr --.parameters --name/string?=null .body=null:
    if not name:
      preferred-name = "constructor"
      this.name = "constructor"
    else:
      preferred-name = name
    is-abstract = false
    is-static = false
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
  toitdoc/List? := null

  constructor.parameter .preferred-name
      --.type=null
      --.initial=null
      --.is-block=false
      --.is-named=false
      --.is-nullable=false
      --.is-final=false:

  constructor.ignored:
    preferred-name = "_"
    name = "_"
    is-block = false
    is-named = false
    is-nullable = false
    initial = null
    type = null
    is-final = false

  constructor.it:
    preferred-name = "it"
    name = "it"
    is-block = false
    is-named = false
    is-nullable = false
    initial = null
    type = null
    is-final = false

  constructor.local .preferred-name
      --.type=null
      --.is-nullable=false
      --.is-final=false
      --.initial/Expression:
    is-block = false
    is-named = false

  constructor.field .preferred-name
      --.type=null
      --.is-nullable=false
      --.is-final=true
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

  /** Adds an if statement. */
  iff condition/Expression then-branch/Statement else-branch/Statement?=null -> none:
    if-statement := If condition then-branch else-branch
    add if-statement

  /** Adds a return statement. */
  ret value/Expression?=null -> none:
    return-statement := Return value
    add return-statement

  /** Adds an assignment statement. */
  assign target/RefTarget value/Expression -> none:
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
An assignment expression (e.g. `foo = bar`).
*/
class Assign extends Expression:
  target/RefTarget
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
  type/RefTarget

  constructor .expression .type:

  accept visitor/NodeVisitor -> any:
    return visitor.visit-As this

/**
An `is` type check expression.
*/
class Is extends Expression:
  expression/Expression
  type/RefTarget

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
A named argument.
*/
class Named extends Expression:
  parameter/VarDefinition
  value/Expression

  constructor .parameter .value:

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
