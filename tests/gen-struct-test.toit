// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import toit-gen

main:
  test-basic-class
  test-classes-and-mixins
  test-implements-and-with
  test-imports-and-exports
  test-import-without-redundant-prefix
  test-import-explicit-rename-prefix
  test-named-constructor
  test-abstract-method
  test-super-call
  test-extends-imported
  test-throw
  test-nullable-field
  test-typed-positional-parameter
  test-typed-named-parameter
  test-nullable-named-parameter
  test-parameter-with-default
  test-named-nullable-with-null-default
  test-library-helpers
  test-class-helpers
  test-sequence-invoke
  test-import-refer
  test-relative-import-bare
  test-relative-import-with-prefix
  test-import-show-all-bare
  test-named-external-constructor
  test-interface-static-method

test-basic-class:
  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS
  fun := toit-gen.Function "myMethod" --parameters=[] --return-type=null
  cls.members.add fun

  seq := toit-gen.Sequence
  seq.add (toit-gen.Return (toit-gen.Literal 42))
  fun.body = seq

  lib := toit-gen.Library "test.toit"
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test.toit"]

  expected := """
    class MyClass:
      my-method:
        return 42"""
  expect-equals expected code.trim

test-classes-and-mixins:
  lib := toit-gen.Library "test5.toit"

  itf := toit-gen.Class "MyInterface" --kind=toit-gen.Class.INTERFACE
  mx := toit-gen.Class "MyMixin" --kind=toit-gen.Class.MIXIN
  abstr := toit-gen.Class "MyAbstract" --kind=toit-gen.Class.CLASS --is-abstract=true

  lib.classes.add itf
  lib.classes.add mx
  lib.classes.add abstr

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test5.toit"]

  expected := """
    interface MyInterface:

    mixin MyMixin:

    abstract class MyAbstract:"""
  expect-equals expected code.trim


test-implements-and-with:
  lib := toit-gen.Library "test-implements.toit"

  itf := toit-gen.Class "Serializable" --kind=toit-gen.Class.INTERFACE
  mx := toit-gen.Class "Printable" --kind=toit-gen.Class.MIXIN
  base := toit-gen.Class "Base" --kind=toit-gen.Class.CLASS

  cls := toit-gen.Class "MyClass"
      --kind=toit-gen.Class.CLASS
      --super-class=(toit-gen.Ref base)
  cls.interfaces.add (toit-gen.Ref itf)
  cls.mixins.add (toit-gen.Ref mx)

  lib.classes.add itf
  lib.classes.add mx
  lib.classes.add base
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-implements.toit"]

  expected := """
    interface Serializable:

    mixin Printable:

    class Base:

    class MyClass extends Base implements Serializable with Printable:"""
  expect-equals expected code.trim

test-imports-and-exports:
  lib := toit-gen.Library "test-imports-and-exports.toit"

  imp := toit-gen.Import ["my-library"]
  imp.prefix = "lib"
  lib.imports.add imp

  exp := toit-gen.Export
  lib.exports.add exp

  local-var := toit-gen.VarDefinition.local "t" --initial=(toit-gen.Literal null)
  local-var.name = "t"

  my-class-var := toit-gen.VarDefinition.local "MyClass" --initial=(toit-gen.Literal null)
  my-class-var.name = "MyClass"
  my-class-ref := toit-gen.ImportedRef imp my-class-var

  other-class-var := toit-gen.VarDefinition.local "OtherClass" --initial=(toit-gen.Literal null)
  other-class-var.name = "OtherClass"
  other-class-ref := toit-gen.Ref other-class-var
  exp.exports.add other-class-ref

  imported-ref := toit-gen.ImportedRef imp local-var

  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement imported-ref)
  fun := toit-gen.Function "wrap" --parameters=[] --return-type=null
  fun.body = seq
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-imports-and-exports.toit"]

  expected := """
    import my-library as lib

    export OtherClass

    wrap:
      lib.t"""
  expect-equals expected code.trim

test-named-constructor:
  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS
  seq := toit-gen.Sequence
  seq.add (toit-gen.Return (toit-gen.Literal 42))
  constr := toit-gen.Function.constr --name="from-json" --parameters=[] seq
  cls.members.add constr

  lib := toit-gen.Library "test.toit"
  lib.classes.add cls
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test.toit"]

  expect (code.contains "constructor.from-json:")
      --message="Expected named constructor"
  expect-not (code.contains "from-json -> ")
      --message="Named constructors should not have return type"

test-abstract-method:
  cls := toit-gen.Class "Base" --kind=toit-gen.Class.CLASS --is-abstract
  map-class := toit-gen.Class.core "Map"
  method := toit-gen.Function "to-json"
      --parameters=[]
      --return-type=(toit-gen.Ref map-class)
      --is-abstract
  cls.members.add method

  lib := toit-gen.Library "test.toit"
  lib.classes.add cls
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test.toit"]

  expect (code.contains "abstract class Base")
      --message="Expected abstract class"
  expect (code.contains "abstract to-json -> Map")
      --message="Expected abstract method without colon"
  expect-not (code.contains "abstract to-json -> Map:")
      --message="Abstract methods should not have colon"

test-super-call:
  cls := toit-gen.Class "Child" --kind=toit-gen.Class.CLASS
  seq := toit-gen.Sequence
  // super.from-json data
  data-param := toit-gen.VarDefinition.parameter "data"
  seq.add (toit-gen.Statement
      (toit-gen.Call toit-gen.Super "from-json" --arguments=[toit-gen.Ref data-param]))
  constr := toit-gen.Function.constr --name="from-json" --parameters=[data-param] seq
  cls.members.add constr

  lib := toit-gen.Library "test.toit"
  lib.classes.add cls
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test.toit"]

  expect (code.contains "super.from-json data")
      --message="Expected super.from-json call"

test-extends-imported:
  // A superclass imported through a prefixed import must render with the
  // prefix: `class Api extends my-library.ApiBase`.
  imp := toit-gen.Import ["my-library"] --preferred-prefix="my-library"
  base := toit-gen.Class.imported "ApiBase"

  cls := toit-gen.Class "Api" --kind=toit-gen.Class.CLASS
      --super-class=(toit-gen.ImportedRef imp base)

  lib := toit-gen.Library "test-extends-imported.toit"
  lib.imports.add imp
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-extends-imported.toit"]

  expect (code.contains "class Api extends my-library.ApiBase")
      --message="Expected the superclass to render through the import prefix"

test-throw:
  lib := toit-gen.Library "test.toit"
  seq := toit-gen.Sequence
  seq.add (toit-gen.Throw (toit-gen.Literal "something went wrong"))
  fun := toit-gen.Function "fail" --parameters=[] --return-type=null
  fun.body = seq
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test.toit"]

  expect (code.contains "throw \"something went wrong\"")
      --message="Expected throw statement"

test-nullable-field:
  // is-nullable on a field renders `?` after the type.
  string-class := toit-gen.Class.core "string"

  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS

  required-field := toit-gen.VarDefinition.field "name"
      --type=(toit-gen.Ref string-class)
      --initial=(toit-gen.Literal "")
      --is-final=false
  optional-field := toit-gen.VarDefinition.field "nick"
      --type=(toit-gen.Ref string-class)
      --is-nullable=true
      --initial=(toit-gen.Literal null)
      --is-final=false
  cls.fields.add required-field
  cls.fields.add optional-field

  lib := toit-gen.Library "test.toit"
  lib.classes.add cls
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test.toit"]

  expect (code.contains "name/string := \"\"")
      --message="Expected non-nullable field without `?`"
  expect (code.contains "nick/string? := null")
      --message="Expected nullable field with `?` after type"

test-import-without-redundant-prefix:
  // When the explicit prefix matches the module's last segment, `as prefix`
  // is redundant and must be suppressed.
  imp := toit-gen.Import ["my-library"]
  imp.preferred-prefix = "my-library"

  target := toit-gen.VarDefinition.local "t" --initial=(toit-gen.Literal null)
  target.name = "t"
  ref := toit-gen.ImportedRef imp target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement ref)
  fun.body = seq

  lib := toit-gen.Library "test-import-redundant.toit"
  lib.imports.add imp
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-import-redundant.toit"]

  expect (code.contains "import my-library")
      --message="Expected plain `import my-library` without redundant `as`"
  expect-not (code.contains "show t")
      --message="No `show t` clause is emitted; refs use the `my-library` prefix"
  expect-not (code.contains "as my-library")
      --message="Did not expect `as my-library` when prefix matches segment"

test-import-explicit-rename-prefix:
  // When the prefix differs from the last segment, `as prefix` must be kept.
  imp := toit-gen.Import ["my-library"]
  imp.preferred-prefix = "lib"

  target := toit-gen.VarDefinition.local "t" --initial=(toit-gen.Literal null)
  target.name = "t"
  ref := toit-gen.ImportedRef imp target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement ref)
  fun.body = seq

  lib := toit-gen.Library "test-import-rename.toit"
  lib.imports.add imp
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-import-rename.toit"]

  expect (code.contains "import my-library as lib")
      --message="Expected `as lib` rename to be preserved"
  expect-not (code.contains "show t")
      --message="No `show t` clause is emitted; refs use the `lib` prefix"

test-typed-positional-parameter:
  // A positional parameter with a type renders as `name/Type`.
  int-class := toit-gen.Class.core "int"

  param := toit-gen.VarDefinition.parameter "x" --type=(toit-gen.Ref int-class)
  fun := toit-gen.Function "foo" --parameters=[param] --return-type=null
  seq := toit-gen.Sequence
  fun.body = seq

  lib := toit-gen.Library "test-typed-positional.toit"
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-typed-positional.toit"]

  expect (code.contains "foo x/int:")
      --message="Expected typed positional parameter `x/int`"

test-typed-named-parameter:
  // A named parameter with a type renders as `--name/Type`.
  int-class := toit-gen.Class.core "int"

  param := toit-gen.VarDefinition.parameter "limit"
      --type=(toit-gen.Ref int-class)
      --is-named=true
  fun := toit-gen.Function "foo" --parameters=[param] --return-type=null
  seq := toit-gen.Sequence
  fun.body = seq

  lib := toit-gen.Library "test-typed-named.toit"
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-typed-named.toit"]

  expect (code.contains "foo --limit/int:")
      --message="Expected typed named parameter `--limit/int`"

test-nullable-named-parameter:
  // A nullable named parameter renders as `--name/Type?`.
  int-class := toit-gen.Class.core "int"

  param := toit-gen.VarDefinition.parameter "limit"
      --type=(toit-gen.Ref int-class)
      --is-named=true
      --is-nullable=true
  fun := toit-gen.Function "foo" --parameters=[param] --return-type=null
  seq := toit-gen.Sequence
  fun.body = seq

  lib := toit-gen.Library "test-nullable-named.toit"
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-nullable-named.toit"]

  expect (code.contains "foo --limit/int?:")
      --message="Expected nullable named parameter `--limit/int?`"

test-parameter-with-default:
  // A parameter with an `initial` Expression renders as `name=value`.
  int-class := toit-gen.Class.core "int"

  param := toit-gen.VarDefinition.parameter "x"
      --type=(toit-gen.Ref int-class)
      --initial=(toit-gen.Literal 42)
  fun := toit-gen.Function "foo" --parameters=[param] --return-type=null
  seq := toit-gen.Sequence
  fun.body = seq

  lib := toit-gen.Library "test-param-default.toit"
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-param-default.toit"]

  expect (code.contains "foo x/int=42:")
      --message="Expected parameter with default `x/int=42`"

test-named-nullable-with-null-default:
  // The common openapi shape: --name/Type?=null.
  int-class := toit-gen.Class.core "int"

  param := toit-gen.VarDefinition.parameter "limit"
      --type=(toit-gen.Ref int-class)
      --is-named=true
      --is-nullable=true
      --initial=(toit-gen.Literal null)
  fun := toit-gen.Function "foo" --parameters=[param] --return-type=null
  seq := toit-gen.Sequence
  fun.body = seq

  lib := toit-gen.Library "test-nullable-default.toit"
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-nullable-default.toit"]

  expect (code.contains "foo --limit/int?=null:")
      --message="Expected named nullable parameter with null default"

test-library-helpers:
  // Library.add-import / add-class / add-function add and return.
  lib := toit-gen.Library "test-lib-helpers.toit"

  // Package-based import; auto-inferred preferred-prefix.
  my-lib-pkg := toit-gen.Package --prefix="my-lib" --id="github.com/example/my-lib"
  imp := lib.add-import my-lib-pkg
  expect-equals 1 lib.imports.size
  expect-identical imp lib.imports[0]
  expect-equals "my-lib" imp.preferred-prefix
  expect-identical my-lib-pkg imp.package

  // --module attaches a submodule path; prefix is the last segment.
  foo-pkg := toit-gen.Package --prefix="foo" --id="github.com/example/foo"
  imp2 := lib.add-import foo-pkg --module="bar"
  expect-equals ["foo", "bar"] imp2.segments
  expect-equals "bar" imp2.preferred-prefix

  // Explicit --preferred-prefix overrides the auto-inferred one.
  imp3 := lib.add-import my-lib-pkg --preferred-prefix="renamed"
  expect-equals "renamed" imp3.preferred-prefix

  cls := lib.add-class "MyClass"
  expect-equals 1 lib.classes.size
  expect-identical cls lib.classes[0]
  expect-equals toit-gen.Class.CLASS cls.kind

  fn := lib.add-function "free" --parameters=[] --return-type=null
  expect-equals 1 lib.functions.size
  expect-identical fn lib.functions[0]

  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  code := generated["test-lib-helpers.toit"]

  expected := """
    class MyClass:

    free:"""
  expect-equals expected code.trim

test-class-helpers:
  // Class.add-field / add-method / add-constructor (unnamed and named)
  // add and return.
  cls := toit-gen.Class "Box" --kind=toit-gen.Class.CLASS

  int-class := toit-gen.Class.core "int"
  field := cls.add-field "value"
      --type=(toit-gen.Ref int-class)
      --is-final=false
      --initial=(toit-gen.Literal 0)
  expect-identical field cls.fields[0]

  method-body := toit-gen.Sequence
  method-body.ret (toit-gen.Ref field)
  m := cls.add-method "get-value"
      --parameters=[]
      --return-type=(toit-gen.Ref int-class)
      method-body
  expect-identical m cls.members[0]

  ctor-body := toit-gen.Sequence
  ctor-body.assign field (toit-gen.Literal 1)
  ctor := cls.add-constructor ctor-body
  expect-identical ctor cls.members[1]

  named-ctor-body := toit-gen.Sequence
  named-ctor-body.assign field (toit-gen.Literal 2)
  named-ctor := cls.add-constructor --name="two" named-ctor-body
  expect-identical named-ctor cls.members[2]

  lib := toit-gen.Library "test-class-helpers.toit"
  lib.classes.add cls
  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-class-helpers.toit"]

  expect (code.contains "value/int := 0")
      --message="Expected field added by add-field"
  expect (code.contains "get-value -> int:")
      --message="Expected method added by add-method"
  expect (code.contains "constructor:")
      --message="Expected unnamed constructor added by add-constructor"
  expect (code.contains "constructor.two:")
      --message="Expected named constructor added by add-constructor --name"

test-sequence-invoke:
  // Sequence.invoke wraps Call(target, method-name) in a Statement.
  obj-var := toit-gen.VarDefinition.local "obj" --initial=(toit-gen.Literal null)
  obj-var.name = "obj"

  seq := toit-gen.Sequence
  seq.invoke (toit-gen.Ref obj-var) "close"
  seq.invoke (toit-gen.Ref obj-var) "set" --arguments=[toit-gen.Literal "k", toit-gen.Literal "v"]

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  fun.body = seq

  lib := toit-gen.Library "test-invoke.toit"
  lib.globals.add obj-var
  lib.functions.add fun
  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-invoke.toit"]

  expect (code.contains "obj.close")
      --message="Expected `obj.close` from invoke"
  expect (code.contains "obj.set \"k\" \"v\"")
      --message="Expected `obj.set` from invoke with arguments"

test-import-refer:
  // Import.refer creates an ImportedRef bound to this import.
  imp := toit-gen.Import ["my-lib"]
  imp.preferred-prefix = "lib"

  target := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  target.name = "x"

  ref := imp.refer target
  expect-identical imp ref.imp
  expect-identical target ref.target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  body := toit-gen.Sequence
  body.add (toit-gen.ExpressionStatement ref)
  fun.body = body

  lib := toit-gen.Library "test-refer.toit"
  lib.imports.add imp
  lib.functions.add fun
  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-refer.toit"]

  expect (code.contains "lib.x")
      --message="Expected `lib.x` rendering for ImportedRef from Import.refer"

test-named-external-constructor:
  // Named.external fabricates the parameter VarDefinition from a string for
  // calls to functions that aren't generated by toit-gen.
  arg := toit-gen.Named.external "all" (toit-gen.Literal "x")
  expect-equals "all" arg.parameter.name

  callee := toit-gen.Function "callee" --parameters=[] --return-type=null
  callee.name = "callee"

  call-expr := toit-gen.Call (toit-gen.Ref callee) --arguments=[arg]
  body := toit-gen.Sequence
  body.add (toit-gen.ExpressionStatement call-expr)
  caller := toit-gen.Function "caller" --parameters=[] --return-type=null
  caller.body = body

  lib := toit-gen.Library "test-named-external.toit"
  lib.functions.add callee
  lib.functions.add caller
  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-named-external.toit"]

  expect (code.contains "--all=\"x\"")
      --message="Expected `--all=\"x\"` from Named.external"

test-interface-static-method:
  // Static members on an interface are not implicitly abstract: they keep
  // their body and need a colon, unlike regular interface members.
  int-class := toit-gen.Class.core "int"

  itf := toit-gen.Class "MyInterface" --kind=toit-gen.Class.INTERFACE

  // A regular (instance) interface member: implicitly abstract, no body.
  itf.members.add
      toit-gen.Function "do-thing" --parameters=[] --return-type=null

  // A static method on the interface: keeps its body.
  static-body := toit-gen.Sequence
  static-body.add (toit-gen.Return (toit-gen.Literal 42))
  static-fn := toit-gen.Function "compute"
      --parameters=[]
      --return-type=(toit-gen.Ref int-class)
  static-fn.body = static-body
  itf.static-functions.add static-fn

  lib := toit-gen.Library "test-interface-static.toit"
  lib.classes.add itf
  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-interface-static.toit"]

  expect (code.contains "static compute -> int:")
      --message="Expected static interface method with colon"
  expect (code.contains "return 42")
      --message="Expected static interface method body"
  // The instance member must still render without a colon.
  expect (code.contains "do-thing\n")
      --message="Expected instance interface member without colon"
  expect-not (code.contains "do-thing:")
      --message="Instance interface members must not have a colon"

test-relative-import-bare:
  // A relative import binds no implicit prefix, so it renders without `as`
  // and its references are unqualified.
  lib := toit-gen.Library "test-relative-bare.toit"
  imp := lib.add-relative-import "openapi"

  target := toit-gen.VarDefinition.local "Thing" --initial=(toit-gen.Literal null)
  target.name = "Thing"
  ref := imp.refer target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement ref)
  fun.body = seq
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib
  code := (program.gen --in-memory)["test-relative-bare.toit"]

  expect (code.contains "import .openapi\n")
      --message="Expected plain `import .openapi` without `as`"
  expect-not (code.contains " as ")
      --message="A relative import without a prefix must not render `as`"
  expect (code.contains "  Thing")
      --message="Expected unqualified `Thing` reference"

test-relative-import-with-prefix:
  // A relative import with an explicit prefix renders `as` and qualifies its
  // references through it.
  lib := toit-gen.Library "test-relative-prefix.toit"
  imp := lib.add-relative-import "openapi" --preferred-prefix="oa"

  target := toit-gen.VarDefinition.local "Thing" --initial=(toit-gen.Literal null)
  target.name = "Thing"
  ref := imp.refer target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement ref)
  fun.body = seq
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib
  code := (program.gen --in-memory)["test-relative-prefix.toit"]

  expect (code.contains "import .openapi as oa")
      --message="Expected `import .openapi as oa` for a prefixed relative import"
  expect (code.contains "oa.Thing")
      --message="Expected `oa.Thing` reference through the prefix"

test-import-show-all-bare:
  // `show *` removes the prefix, so references must be unqualified.
  lib := toit-gen.Library "test-show-all.toit"
  pkg := toit-gen.Package --prefix="my-lib" --id="github.com/example/my-lib"
  imp := lib.add-import pkg --show-all

  target := toit-gen.VarDefinition.local "Thing" --initial=(toit-gen.Literal null)
  target.name = "Thing"
  ref := imp.refer target

  fun := toit-gen.Function "use" --parameters=[] --return-type=null
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement ref)
  fun.body = seq
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib
  code := (program.gen --in-memory)["test-show-all.toit"]

  expect (code.contains "import my-lib show *")
      --message="Expected `import my-lib show *`"
  expect-not (code.contains "my-lib.Thing")
      --message="`show *` removes the prefix, so references must be unqualified"
  expect (code.contains "  Thing")
      --message="Expected unqualified `Thing` reference under `show *`"
