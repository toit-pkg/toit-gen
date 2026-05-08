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
  test-named-constructor
  test-abstract-method
  test-super-call
  test-throw
  test-nullable-field

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
    import my-library as lib show MyClass t

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
