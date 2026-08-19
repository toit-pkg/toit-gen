// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import toit-gen

main:
  test-while-basic
  test-while-nested
  test-while-with-break-continue
  test-for-basic
  test-for-with-local-definition
  test-break-no-value
  test-break-with-value
  test-break-with-complex-value
  test-continue
  test-try-finally-basic
  test-try-finally-nested-in-loop
  test-sequence-convenience-whle
  test-sequence-convenience-brk-cont
  test-sequence-convenience-try-finally

/// Helper that wraps a statement body in a function/library/program and
/// returns the generated code string.
gen-body body/toit-gen.Statement -> string:
  lib := toit-gen.Library "test.toit"
  fun := toit-gen.Function "test-fn" --parameters=[] --return-type=null
  fun.name = "test-fn"
  fun.body = body
  lib.functions.add fun
  program := toit-gen.Program
  program.libraries.add lib
  generated := program.gen --in-memory
  return generated["test.toit"]

test-while-basic:
  // while true:
  //   print 1
  print-var := toit-gen.VarDefinition.local "print" --initial=(toit-gen.Literal null)
  print-var.name = "print"
  print-ref := toit-gen.Ref print-var
  print-call := toit-gen.Call print-ref --arguments=[toit-gen.Literal 1]

  whl := toit-gen.While (toit-gen.Literal true)
      (toit-gen.ExpressionStatement print-call)

  seq := toit-gen.Sequence
  seq.add whl

  code := gen-body seq
  expected := """
    test-fn:
      while true:
        print 1"""
  expect-equals expected code.trim

test-while-nested:
  // while true:
  //   while false:
  //     42
  inner := toit-gen.While (toit-gen.Literal false)
      (toit-gen.ExpressionStatement (toit-gen.Literal 42))
  outer := toit-gen.While (toit-gen.Literal true) inner

  seq := toit-gen.Sequence
  seq.add outer

  code := gen-body seq
  expected := """
    test-fn:
      while true:
        while false:
          42"""
  expect-equals expected code.trim

test-while-with-break-continue:
  // while true:
  //   continue
  //   break
  inner-seq := toit-gen.Sequence
  inner-seq.add (toit-gen.Continue)
  inner-seq.add (toit-gen.Break)

  whl := toit-gen.While (toit-gen.Literal true) inner-seq

  seq := toit-gen.Sequence
  seq.add whl

  code := gen-body seq
  expected := """
    test-fn:
      while true:
        continue
        break"""
  expect-equals expected code.trim

test-for-basic:
  // for i := 0; i < 10; i = i + 1:
  //   print i
  i-var := toit-gen.VarDefinition.local "i" --initial=(toit-gen.Literal 0)
  i-var.name = "i"
  i-ref := toit-gen.Ref i-var

  init := toit-gen.LocalDefinition i-var
  condition := toit-gen.Binary i-ref "<" (toit-gen.Literal 10)
  update := toit-gen.Assign i-ref (toit-gen.Binary i-ref "+" (toit-gen.Literal 1))

  print-var := toit-gen.VarDefinition.local "print" --initial=(toit-gen.Literal null)
  print-var.name = "print"
  print-ref := toit-gen.Ref print-var
  print-call := toit-gen.Call print-ref --arguments=[i-ref]
  body := toit-gen.ExpressionStatement print-call

  for-stmt := toit-gen.For init condition update body

  seq := toit-gen.Sequence
  seq.add for-stmt

  code := gen-body seq
  expected := """
    test-fn:
      for i := 0; i < 10; i = i + 1:
        print i"""
  expect-equals expected code.trim

test-for-with-local-definition:
  // for j := 5; j > 0; j = j - 1:
  //   j
  j-var := toit-gen.VarDefinition.local "j" --initial=(toit-gen.Literal 5)
  j-var.name = "j"
  j-ref := toit-gen.Ref j-var

  init := toit-gen.LocalDefinition j-var
  condition := toit-gen.Binary j-ref ">" (toit-gen.Literal 0)
  update := toit-gen.Assign j-ref (toit-gen.Binary j-ref "-" (toit-gen.Literal 1))
  body := toit-gen.ExpressionStatement j-ref

  for-stmt := toit-gen.For init condition update body

  seq := toit-gen.Sequence
  seq.add for-stmt

  code := gen-body seq
  expected := """
    test-fn:
      for j := 5; j > 0; j = j - 1:
        j"""
  expect-equals expected code.trim

test-break-no-value:
  seq := toit-gen.Sequence
  seq.add (toit-gen.Break)

  code := gen-body seq
  expected := """
    test-fn:
      break"""
  expect-equals expected code.trim

test-break-with-value:
  x-var := toit-gen.VarDefinition.local "x" --initial=(toit-gen.Literal null)
  x-var.name = "x"
  x-ref := toit-gen.Ref x-var

  seq := toit-gen.Sequence
  seq.add (toit-gen.Break x-ref)

  code := gen-body seq
  expected := """
    test-fn:
      break x"""
  expect-equals expected code.trim

test-break-with-complex-value:
  // break (foo + bar)
  foo-var := toit-gen.VarDefinition.local "foo" --initial=(toit-gen.Literal null)
  foo-var.name = "foo"
  bar-var := toit-gen.VarDefinition.local "bar" --initial=(toit-gen.Literal null)
  bar-var.name = "bar"
  complex := toit-gen.Binary (toit-gen.Ref foo-var) "+" (toit-gen.Ref bar-var)

  seq := toit-gen.Sequence
  seq.add (toit-gen.Break complex)

  code := gen-body seq
  expected := """
    test-fn:
      break (foo + bar)"""
  expect-equals expected code.trim

test-continue:
  seq := toit-gen.Sequence
  seq.add (toit-gen.Continue)

  code := gen-body seq
  expected := """
    test-fn:
      continue"""
  expect-equals expected code.trim

test-try-finally-basic:
  // try:
  //   42
  // finally:
  //   0
  tf := toit-gen.TryFinally
      (toit-gen.ExpressionStatement (toit-gen.Literal 42))
      (toit-gen.ExpressionStatement (toit-gen.Literal 0))

  seq := toit-gen.Sequence
  seq.add tf

  code := gen-body seq
  expected := """
    test-fn:
      try:
        42
      finally:
        0"""
  expect-equals expected code.trim

test-try-finally-nested-in-loop:
  // while true:
  //   try:
  //     break
  //   finally:
  //     1
  tf := toit-gen.TryFinally
      (toit-gen.Break)
      (toit-gen.ExpressionStatement (toit-gen.Literal 1))

  whl := toit-gen.While (toit-gen.Literal true) tf

  seq := toit-gen.Sequence
  seq.add whl

  code := gen-body seq
  expected := """
    test-fn:
      while true:
        try:
          break
        finally:
          1"""
  expect-equals expected code.trim

test-sequence-convenience-whle:
  // Test Sequence.whle convenience method.
  seq := toit-gen.Sequence
  seq.whle (toit-gen.Literal true) (toit-gen.ExpressionStatement (toit-gen.Literal 1))

  code := gen-body seq
  expected := """
    test-fn:
      while true:
        1"""
  expect-equals expected code.trim

test-sequence-convenience-brk-cont:
  // Test Sequence.brk and Sequence.cont convenience methods.
  seq := toit-gen.Sequence
  seq.brk
  seq.cont

  code := gen-body seq
  expected := """
    test-fn:
      break
      continue"""
  expect-equals expected code.trim

test-sequence-convenience-try-finally:
  // Test Sequence.try-finally convenience method.
  seq := toit-gen.Sequence
  seq.try-finally
      (toit-gen.ExpressionStatement (toit-gen.Literal 42))
      (toit-gen.ExpressionStatement (toit-gen.Literal 0))

  code := gen-body seq
  expected := """
    test-fn:
      try:
        42
      finally:
        0"""
  expect-equals expected code.trim
