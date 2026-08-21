// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import toit-gen

main:
  test-collects-structural-diagnostics
  test-generation-validates-before-naming
  test-parenthesized-multi-block-call
  test-block-position
  test-import-ownership
  test-field-parameter-ownership

test-collects-structural-diagnostics:
  body := toit-gen.Sequence
  body.add (toit-gen.Literal [1])
  body.add
      toit-gen.StringInterpolation [
        "value=",
        toit-gen.Literal 1,
      ]
  body.add
      toit-gen.MapLiteral
          [toit-gen.Literal "key"]
          []

  program := program-with-body "invalid-structures.toit" body
  diagnostics := program.validate
  codes := diagnostics.map: it.code

  expect-equals 3 diagnostics.size
  expect (codes.contains "UNSUPPORTED_LITERAL")
  expect (codes.contains "INVALID_INTERPOLATION_SHAPE")
  expect (codes.contains "MISMATCHED_MAP_ENTRIES")
  diagnostics.do: | diagnostic/toit-gen.ValidationDiagnostic |
    expect-equals "invalid-structures.toit" diagnostic.library-path

test-generation-validates-before-naming:
  invalid-class := toit-gen.Class "Broken" --kind=99
  library := toit-gen.Library "invalid-class.toit"
  library.classes.add invalid-class
  program := toit-gen.Program
  program.libraries.add library

  error := catch: program.gen --in-memory
  expect (error is toit-gen.ValidationError)
      --message="Generation must throw a structured ValidationError"
  validation-error := error as toit-gen.ValidationError
  expect-equals "INVALID_CLASS_KIND" validation-error.diagnostics.first.code
  expect ("$validation-error".contains "INVALID_CLASS_KIND")
  expect-null invalid-class.name

test-parenthesized-multi-block-call:
  inner := toit-gen.Call
      (external-ref "combine")
      --arguments=[simple-block, simple-block]
  outer := toit-gen.Call
      (external-ref "consume")
      --arguments=[inner]
  body := toit-gen.Sequence
  body.add outer

  diagnostics := (program-with-body "multi-block.toit" body).validate
  expect-equals 1 diagnostics.size
  expect-equals
      "MULTIPLE_BLOCKS_IN_PARENTHESIZED_CALL"
      diagnostics.first.code

test-block-position:
  body := toit-gen.Sequence
  body.add simple-block

  diagnostics := (program-with-body "block-position.toit" body).validate
  expect-equals 1 diagnostics.size
  expect-equals "UNSUPPORTED_BLOCK_POSITION" diagnostics.first.code

test-import-ownership:
  owner := toit-gen.Library "owner.toit"
  imp := owner.add-relative-import "dependency" --preferred-prefix="dependency"
  imported := imp.refer (toit-gen.Class.imported "Thing")

  body := toit-gen.Sequence
  body.add imported
  consumer := library-with-body "consumer.toit" body

  program := toit-gen.Program
  program.libraries.add owner
  program.libraries.add consumer
  diagnostics := program.validate

  expect-equals 1 diagnostics.size
  expect-equals "FOREIGN_IMPORT_REFERENCE" diagnostics.first.code
  expect-equals "consumer.toit" diagnostics.first.library-path

test-field-parameter-ownership:
  first := toit-gen.Class "First" --kind=toit-gen.Class.CLASS
  second := toit-gen.Class "Second" --kind=toit-gen.Class.CLASS
  foreign-field := first.add-field "value"
  second.add-constructor
      --parameters=[toit-gen.VarDefinition.field-parameter foreign-field]
      toit-gen.Sequence

  library := toit-gen.Library "field-parameter.toit"
  library.classes.add first
  library.classes.add second
  program := toit-gen.Program
  program.libraries.add library
  diagnostics := program.validate

  expect-equals 1 diagnostics.size
  expect-equals "FOREIGN_FIELD_PARAMETER" diagnostics.first.code

simple-block -> toit-gen.Block:
  return toit-gen.Block (toit-gen.ExpressionStatement (toit-gen.Literal 1))

external-ref name/string -> toit-gen.Ref:
  function := toit-gen.Function name --parameters=[] --return-type=null
  function.name = name
  return toit-gen.Ref function

program-with-body path/string body/toit-gen.Statement -> toit-gen.Program:
  program := toit-gen.Program
  program.libraries.add (library-with-body path body)
  return program

library-with-body path/string body/toit-gen.Statement -> toit-gen.Library:
  function := toit-gen.Function "generated"
      --parameters=[]
      --return-type=null
      body
  library := toit-gen.Library path
  library.functions.add function
  return library
