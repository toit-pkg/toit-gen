// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Validates toit-gen ASTs before naming or rendering.
*/

import .toit-gen
import .visitor show TraversingVisitor

validate-program_ program/Program -> List:
  validator := ValidationVisitor_
  program.accept validator
  return validator.diagnostics

class ValidationVisitor_ extends TraversingVisitor:
  diagnostics/List ::= []  // Of ValidationDiagnostic.
  current-library_/Library? := null
  current-class_/Class? := null
  parenthesized-depth_/int := 0
  block-allowed_/bool := false
  named-allowed_/bool := false

  report_ code/string message/string node/Node -> none:
    library-path/string? := null
    if current-library_: library-path = current-library_.path
    diagnostics.add
        ValidationDiagnostic code message node --library-path=library-path

  validate-toitdoc_ owner/Node toitdoc/List? -> none:
    if not toitdoc: return
    toitdoc.do: | part |
      if part is string or part is ToitdocNameRef or part is ToitdocExactRef or part is ToitdocSuperRef:
        continue.do
      report_ "UNSUPPORTED_TOITDOC_PART"
          "Toitdoc parts must be strings or Toitdoc reference objects"
          owner

  needs-parens_ node/Expression -> bool:
    if node is Call:
      call := node as Call
      if not call.arguments.is-empty: return true
      if call.target is Ref:
        target := (call.target as Ref).target
        if target is Class: return true
        if target is Function and (target as Function).is-constructor: return true
      return false
    return node is Binary
        or node is Ternary
        or node is Unary
        or node is As
        or node is Is

  visit-Program node/Program -> any:
    paths := {}
    node.libraries.do: | library |
      if library is not Library:
        report_ "INVALID_PROGRAM_ENTRY"
            "Program.libraries may only contain Library nodes"
            node
        continue.do
      if paths.contains library.path:
        report_ "DUPLICATE_LIBRARY_PATH"
            "Multiple libraries render to '$(library.path)'"
            library
      else:
        paths.add library.path
      library.accept this
    return null

  visit-Library node/Library -> any:
    old := current-library_
    current-library_ = node
    validate-toitdoc_ node node.toitdoc
    if not node.statics.is-empty:
      report_ "UNSUPPORTED_LIBRARY_STATICS"
          "Library.statics is not supported by the renderer"
          node
    super node
    current-library_ = old
    return null

  visit-Import node/Import -> any:
    if node.segments.is-empty:
      report_ "INVALID_IMPORT_PATH" "An import path must have at least one segment" node
      return null
    node.segments.do: | segment |
      if segment is not string or segment.is-empty:
        report_ "INVALID_IMPORT_PATH"
            "Import path segments must be non-empty strings"
            node
    return null

  visit-Class node/Class -> any:
    if node.kind != Class.CLASS and node.kind != Class.INTERFACE and node.kind != Class.MIXIN:
      report_ "INVALID_CLASS_KIND" "Class.kind is not a supported declaration kind" node

    old := current-class_
    current-class_ = node
    validate-toitdoc_ node node.toitdoc
    super node
    current-class_ = old
    return null

  visit-Function node/Function -> any:
    is-interface-member := current-class_
        and current-class_.kind == Class.INTERFACE
        and current-class_.members.contains node

    if node.is-constructor:
      if not current-class_ or not current-class_.members.contains node:
        report_ "INVALID_CONSTRUCTOR_LOCATION"
            "Constructors must be instance members of a class, interface, or mixin"
            node
    else if node.is-abstract and node.body:
      report_ "ABSTRACT_FUNCTION_BODY"
          "Abstract functions cannot have a body"
          node
    else if is-interface-member and node.body:
      report_ "INTERFACE_FUNCTION_BODY"
          "Instance interface functions cannot have a body"
          node
    node.parameters.do: | parameter/VarDefinition |
      field := parameter.initializes-field
      if not field: continue.do
      if not node.is-constructor:
        report_ "FIELD_PARAMETER_OUTSIDE_CONSTRUCTOR"
            "A field-initializing parameter may only belong to a constructor"
            parameter
      else if not current-class_ or not current-class_.fields.contains field:
        report_ "FOREIGN_FIELD_PARAMETER"
            "A field-initializing parameter must target a field of its constructor's class"
            parameter

    validate-toitdoc_ node node.toitdoc
    super node
    return null

  visit-VarDefinition node/VarDefinition -> any:
    validate-toitdoc_ node node.toitdoc
    if node.is-nullable and not node.type:
      report_ "NULLABLE_WITHOUT_TYPE"
          "A nullable variable must have an explicit type"
          node
    if node.initializes-field and node.is-block:
      report_ "BLOCK_FIELD_PARAMETER"
          "A field-initializing parameter cannot be a block parameter"
          node
    return super node

  visit-Call node/Call -> any:
    block-count := 0
    node.arguments.do: | argument |
      if argument is Block:
        block-count++
      else if argument is Named and (argument as Named).value is Block:
        block-count++

    if parenthesized-depth_ > 0 and block-count > 1:
      report_ "MULTIPLE_BLOCKS_IN_PARENTHESIZED_CALL"
          "A parenthesized call cannot render multiple block arguments"
          node

    node.target.accept this
    node.arguments.do: | argument |
      if argument is not Expression:
        report_ "INVALID_CALL_ARGUMENT"
            "Call.arguments may only contain Expression nodes"
            node
        continue.do

      old-block := block-allowed_
      old-named := named-allowed_
      block-allowed_ = argument is Block
          or (argument is Named and (argument as Named).value is Block)
      named-allowed_ = argument is Named

      parenthesized := needs-parens_ argument
      if parenthesized: parenthesized-depth_++
      argument.accept this
      if parenthesized: parenthesized-depth_--

      block-allowed_ = old-block
      named-allowed_ = old-named
    return null

  visit-Block node/Block -> any:
    if not block-allowed_:
      report_ "UNSUPPORTED_BLOCK_POSITION"
          "Blocks are only supported as direct call arguments"
          node
    old := block-allowed_
    block-allowed_ = false
    super node
    block-allowed_ = old
    return null

  visit-Named node/Named -> any:
    if not named-allowed_:
      report_ "UNSUPPORTED_NAMED_POSITION"
          "Named arguments are only supported as direct call arguments"
          node
    old := named-allowed_
    named-allowed_ = false
    super node
    named-allowed_ = old
    return null

  visit-Literal node/Literal -> any:
    value := node.value
    supported := value == null
        or value is string
        or value is int
        or value is float
        or value is bool
        or (value is List and value.is-empty)
        or (value is Map and value.is-empty)
    if not supported:
      report_ "UNSUPPORTED_LITERAL"
          "Literal supports scalars, null, and empty List or Map values"
          node
    return null

  visit-ImportedRef node/ImportedRef -> any:
    if not current-library_ or not current-library_.imports.contains node.imp:
      report_ "FOREIGN_IMPORT_REFERENCE"
          "An ImportedRef must use an import owned by its containing library"
          node
    return null

  visit-StringInterpolation node/StringInterpolation -> any:
    if node.parts.is-empty or node.parts.size % 2 == 0:
      report_ "INVALID_INTERPOLATION_SHAPE"
          "StringInterpolation.parts must have odd length"
          node
    for i := 0; i < node.parts.size; i++:
      part := node.parts[i]
      if i % 2 == 0:
        if part is not string:
          report_ "INVALID_INTERPOLATION_PART"
              "Even StringInterpolation parts must be strings"
              node
      else if part is Expression:
        part.accept this
      else:
        report_ "INVALID_INTERPOLATION_PART"
            "Odd StringInterpolation parts must be expressions"
            node
    return null

  visit-ListLiteral node/ListLiteral -> any:
    node.elements.do: | element |
      if element is Expression:
        element.accept this
      else:
        report_ "INVALID_LIST_ELEMENT"
            "ListLiteral.elements may only contain Expression nodes"
            node
    return null

  visit-MapLiteral node/MapLiteral -> any:
    if node.keys.size != node.values.size:
      report_ "MISMATCHED_MAP_ENTRIES"
          "MapLiteral.keys and MapLiteral.values must have equal length"
          node
    node.keys.do: | key |
      if key is Expression:
        key.accept this
      else:
        report_ "INVALID_MAP_KEY"
            "MapLiteral.keys may only contain Expression nodes"
            node
    node.values.do: | value |
      if value is Expression:
        value.accept this
      else:
        report_ "INVALID_MAP_VALUE"
            "MapLiteral.values may only contain Expression nodes"
            node
    return null

  visit-SetLiteral node/SetLiteral -> any:
    node.elements.do: | element |
      if element is Expression:
        element.accept this
      else:
        report_ "INVALID_SET_ELEMENT"
            "SetLiteral.elements may only contain Expression nodes"
            node
    return null
