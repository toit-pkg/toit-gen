// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import toit-gen

main:
  test-unary-not
  test-unary-negate
  test-unary-nested-with-binary
  test-string-interpolation-simple-ref
  test-string-interpolation-complex-expr
  test-string-interpolation-multiple
  test-string-interpolation-no-interpolation
  test-list-literal
  test-map-literal
  test-set-literal
  test-index-slice-both-bounds
  test-index-slice-from-only
  test-index-slice-to-only

/// Helper that wraps an expression in a statement/function/library/program and
/// returns the generated code string.
gen-expr expr/toit-gen.Expression -> string:
  seq := toit-gen.Sequence
  seq.add (toit-gen.ExpressionStatement expr)
  lib := toit-gen.Library "test.toit"
  fun := toit-gen.Function "test-fn" --parameters=[] --return-type=null
  fun.name = "test-fn"
  fun.body = seq
  lib.functions.add fun
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  return generated["test.toit"]

test-unary-not:
  // not x
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  not-expr := toit-gen.Unary "not" x-ref
  code := gen-expr not-expr
  expected := """
    test-fn:
      not x"""
  expect-equals expected code.trim

  // not (a == b)
  a-var := toit-gen.VarDefinition.local "a" --initial=(toit-gen.Literal null)
  a-var.name = "a"
  b-var := toit-gen.VarDefinition.local "b" --initial=(toit-gen.Literal null)
  b-var.name = "b"
  eq := toit-gen.Binary (toit-gen.Ref a-var) "==" (toit-gen.Ref b-var)
  not-eq := toit-gen.Unary "not" eq
  code2 := gen-expr not-eq
  expected2 := """
    test-fn:
      not (a == b)"""
  expect-equals expected2 code2.trim

test-unary-negate:
  // -x
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  neg := toit-gen.Unary "-" x-ref
  code := gen-expr neg
  expected := """
    test-fn:
      -x"""
  expect-equals expected code.trim

  // -(a + b)
  a-var := toit-gen.VarDefinition.local "a" --initial=(toit-gen.Literal null)
  a-var.name = "a"
  b-var := toit-gen.VarDefinition.local "b" --initial=(toit-gen.Literal null)
  b-var.name = "b"
  sum := toit-gen.Binary (toit-gen.Ref a-var) "+" (toit-gen.Ref b-var)
  neg-sum := toit-gen.Unary "-" sum
  code2 := gen-expr neg-sum
  expected2 := """
    test-fn:
      -(a + b)"""
  expect-equals expected2 code2.trim

test-unary-nested-with-binary:
  // not (not x)
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  inner-not := toit-gen.Unary "not" x-ref
  outer-not := toit-gen.Unary "not" inner-not
  code := gen-expr outer-not
  expected := """
    test-fn:
      not (not x)"""
  expect-equals expected code.trim

test-string-interpolation-simple-ref:
  // "Hello $name"
  name-var := toit-gen.VarDefinition.local "name" --initial=(toit-gen.Literal null)
  name-var.name = "name"
  name-ref := toit-gen.Ref name-var

  interp := toit-gen.StringInterpolation ["Hello ", name-ref, ""]
  code := gen-expr interp
  expected := """
    test-fn:
      "Hello \$name\""""
  expect-equals expected code.trim

test-string-interpolation-complex-expr:
  // "Result: $(a + b)"
  a-var := toit-gen.VarDefinition.local "a" --initial=(toit-gen.Literal null)
  a-var.name = "a"
  b-var := toit-gen.VarDefinition.local "b" --initial=(toit-gen.Literal null)
  b-var.name = "b"
  sum := toit-gen.Binary (toit-gen.Ref a-var) "+" (toit-gen.Ref b-var)

  interp := toit-gen.StringInterpolation ["Result: ", sum, ""]
  code := gen-expr interp
  expected := """
    test-fn:
      "Result: \$(a + b)\""""
  expect-equals expected code.trim

test-string-interpolation-multiple:
  // "$a and $b equals $(a + b)"
  a-var := toit-gen.VarDefinition.local "a" --initial=(toit-gen.Literal null)
  a-var.name = "a"
  b-var := toit-gen.VarDefinition.local "b" --initial=(toit-gen.Literal null)
  b-var.name = "b"
  a-ref := toit-gen.Ref a-var
  b-ref := toit-gen.Ref b-var
  sum := toit-gen.Binary (toit-gen.Ref a-var) "+" (toit-gen.Ref b-var)

  interp := toit-gen.StringInterpolation ["", a-ref, " and ", b-ref, " equals ", sum, ""]
  code := gen-expr interp
  expected := """
    test-fn:
      "\$a and \$b equals \$(a + b)\""""
  expect-equals expected code.trim

test-string-interpolation-no-interpolation:
  // "just a string" - no expressions, length 1.
  interp := toit-gen.StringInterpolation ["just a string"]
  code := gen-expr interp
  expected := """
    test-fn:
      "just a string\""""
  expect-equals expected code.trim

test-list-literal:
  // [1, 2, 3]
  list := toit-gen.ListLiteral [toit-gen.Literal 1, toit-gen.Literal 2, toit-gen.Literal 3]
  code := gen-expr list
  expected := """
    test-fn:
      [1, 2, 3]"""
  expect-equals expected code.trim

test-map-literal:
  // {"a": 1, "b": 2}
  map := toit-gen.MapLiteral
      [toit-gen.Literal "a", toit-gen.Literal "b"]
      [toit-gen.Literal 1, toit-gen.Literal 2]
  code := gen-expr map
  expected := """
    test-fn:
      {"a": 1, "b": 2}"""
  expect-equals expected code.trim

test-set-literal:
  // {1, 2, 3}
  set := toit-gen.SetLiteral [toit-gen.Literal 1, toit-gen.Literal 2, toit-gen.Literal 3]
  code := gen-expr set
  expected := """
    test-fn:
      {1, 2, 3}"""
  expect-equals expected code.trim

test-index-slice-both-bounds:
  // x[1..3]
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  slice := toit-gen.IndexSlice x-ref --from=(toit-gen.Literal 1) --to=(toit-gen.Literal 3)
  code := gen-expr slice
  expected := """
    test-fn:
      x[1..3]"""
  expect-equals expected code.trim

test-index-slice-from-only:
  // x[2..]
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  slice := toit-gen.IndexSlice x-ref --from=(toit-gen.Literal 2)
  code := gen-expr slice
  expected := """
    test-fn:
      x[2..]"""
  expect-equals expected code.trim

test-index-slice-to-only:
  // x[..5]
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  slice := toit-gen.IndexSlice x-ref --to=(toit-gen.Literal 5)
  code := gen-expr slice
  expected := """
    test-fn:
      x[..5]"""
  expect-equals expected code.trim
