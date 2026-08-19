// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import host.directory
import host.file
import host.os
import toit-gen

GOLD-DIR ::= "tests/gold"
UPDATE-ENV ::= "UPDATE_GOLD"

main:
  update := os.env.get UPDATE-ENV
  cases := [
    ["declarations.toit.gold", generate-declarations],
    ["expressions.toit.gold", generate-expressions],
    ["qualified-references.toit.gold", generate-qualified-references],
  ]

  if update: directory.mkdir --recursive GOLD-DIR
  cases.do: | entry/List |
    name/string := entry[0]
    actual/string := normalize-gold entry[1]
    path := "$GOLD-DIR/$name"
    if update:
      file.write-contents --path=path actual
      print "updated $path"
      continue.do

    expect (file.is-file path)
        --message="Missing $path. Run `make update-gold` to create it."
    expected := (file.read-contents path).to-string.replace --all "\r" ""
    actual = actual.replace --all "\r" ""
    expect-equals expected actual

normalize-gold source/string -> string:
  return (source.trim --right) + "\n"

generate-declarations -> string:
  library := toit-gen.Library "declarations.toit"
  library.toitdoc = ["Representative generated declarations."]
  core-import := library.add-core-import
  string-type := core-import.refer (toit-gen.Class.core "string")
  int-type := core-import.refer (toit-gen.Class.core "int")

  named := toit-gen.Class "Named" --kind=toit-gen.Class.INTERFACE
  named.toitdoc = ["Exposes a name."]
  named.members.add
      toit-gen.Function "name"
          --parameters=[]
          --return-type=string-type
          --is-abstract

  person := toit-gen.Class "Person" --kind=toit-gen.Class.CLASS
  person.toitdoc = ["A generated person model."]
  person.interfaces.add (toit-gen.Ref named)
  name-field := person.add-field "name" --type=string-type
  age-field := person.add-field "age" --type=int-type --is-nullable=true
  person.add-constructor
      --parameters=[
        toit-gen.VarDefinition.field-parameter name-field,
        toit-gen.VarDefinition.field-parameter age-field
            --is-named
            --initial=(toit-gen.Literal null),
      ]
      toit-gen.Sequence

  describe-body := toit-gen.Sequence
  describe-body.ret
      toit-gen.StringInterpolation [
        "",
        toit-gen.Ref name-field,
        "-age=",
        toit-gen.Ref age-field,
        "",
      ]
  person.add-method "describe"
      --parameters=[]
      --return-type=string-type
      describe-body

  library.classes.add named
  library.classes.add person
  return generate-library library

generate-expressions -> string:
  int-type := toit-gen.Ref (toit-gen.Class.core "int")
  value := toit-gen.VarDefinition.parameter "value" --type=int-type
  limit := toit-gen.VarDefinition.parameter "limit"
      --type=int-type
      --initial=(toit-gen.Literal 10)
      --is-named

  body := toit-gen.Sequence
  doubled := body.define "doubled" --type=int-type
      (toit-gen.Ternary
          (toit-gen.Binary (toit-gen.Ref value) ">" (toit-gen.Literal 0))
          (toit-gen.Binary (toit-gen.Ref value) "*" (toit-gen.Literal 2))
          (toit-gen.Unary "-" (toit-gen.Ref value)))
  label := body.define "label"
      (toit-gen.StringInterpolation [
        "value=",
        toit-gen.Ref value,
        "-limit",
      ])
  body.define "metadata"
      (toit-gen.MapLiteral
          [toit-gen.Literal "label"]
          [toit-gen.Ref label])
  body.define "values"
      (toit-gen.ListLiteral [toit-gen.Ref value, toit-gen.Ref doubled])

  then-body := toit-gen.Sequence
  then-body.ret (toit-gen.Ref doubled)
  else-body := toit-gen.Sequence
  else-body.add
      toit-gen.Throw
          toit-gen.StringInterpolation [
            "too-small-",
            toit-gen.Ref value,
            ".detail",
          ]
  body.iff
      (toit-gen.Binary (toit-gen.Ref doubled) ">" (toit-gen.Ref limit))
      then-body
      else-body

  function := toit-gen.Function "classify"
      --parameters=[value, limit]
      --return-type=int-type
      body
  library := toit-gen.Library "expressions.toit"
  library.functions.add function
  return generate-library library

generate-qualified-references -> string:
  library := toit-gen.Library "qualified-references.toit"
  core-import := library.add-core-import
  core-map := core-import.refer (toit-gen.Class.core "Map")
  state-import := toit-gen.Import ["state"] --preferred-prefix="state"
  library.imports.add state-import

  external := toit-gen.VarDefinition.local "current"
      --initial=(toit-gen.Literal null)
  external.name = "current"
  external-ref := state-import.refer external
  value := toit-gen.VarDefinition.parameter "value" --type=core-map

  body := toit-gen.Sequence
  body.assign external-ref (toit-gen.Ref value)
  body.add (toit-gen.As (toit-gen.Ref value) core-map)
  body.add (toit-gen.Is (toit-gen.Ref value) core-map)
  body.add
      toit-gen.StringInterpolation [
        "current=",
        external-ref,
        "-entry",
      ]
  body.ret (toit-gen.Ref value)

  library.classes.add
      toit-gen.Class "Map" --kind=toit-gen.Class.CLASS
  library.functions.add
      toit-gen.Function "qualified"
          --parameters=[value]
          --return-type=core-map
          body
  return generate-library library

generate-library library/toit-gen.Library -> string:
  program := toit-gen.Program
  program.libraries.add library
  return (program.gen --in-memory)[library.path]
