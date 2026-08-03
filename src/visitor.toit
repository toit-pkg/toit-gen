// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .toit-gen
import .toit-gen show Lambda

/**
A visitor interface for all AST nodes.
*/
interface NodeVisitor:
  visit-Program node/Program -> any
  visit-Library node/Library -> any

  visit-Import node/Import -> any
  visit-Export node/Export -> any

  visit-Class node/Class -> any
  visit-Function node/Function -> any
  visit-Operator node/Function -> any

  visit-VarDefinition node/VarDefinition -> any

  // Statements.
  visit-Sequence node/Sequence -> any
  visit-If node/If -> any
  visit-While node/While -> any
  visit-For node/For -> any
  visit-TryFinally node/TryFinally -> any
  visit-Return node/Return -> any
  visit-Break node/Break -> any
  visit-Continue node/Continue -> any
  visit-ExpressionStatement node/ExpressionStatement -> any
  visit-LocalDefinition node/LocalDefinition -> any
  visit-Throw node/Throw -> any

  // Expressions.
  visit-Call node/Call -> any
  visit-Index node/Index -> any
  visit-IndexAssign node/IndexAssign -> any
  visit-IndexSlice node/IndexSlice -> any
  visit-Assign node/Assign -> any
  visit-Block node/Block -> any
  visit-Lambda node/Lambda -> any
  visit-Literal node/Literal -> any
  visit-LateInitialized node/LateInitialized -> any
  visit-Ref node/Ref -> any
  visit-ImportedRef node/ImportedRef -> any
  visit-As node/As -> any
  visit-Is node/Is -> any
  visit-Binary node/Binary -> any
  visit-Ternary node/Ternary -> any
  visit-Unary node/Unary -> any
  visit-Named node/Named -> any
  visit-StringInterpolation node/StringInterpolation -> any
  visit-ListLiteral node/ListLiteral -> any
  visit-MapLiteral node/MapLiteral -> any
  visit-SetLiteral node/SetLiteral -> any
  visit-Super node/Super -> any

/**
A standard visitor that recursively visits all child nodes.

Subclass this visitor to traverse the entire AST.
*/
class TraversingVisitor implements NodeVisitor:
  visit-Program node/Program -> any:
    node.libraries.do: it.accept this
    return null

  visit-Library node/Library -> any:
    node.imports.do: it.accept this
    node.exports.do: it.accept this
    node.classes.do: it.accept this
    node.globals.do: it.accept this
    node.functions.do: it.accept this
    return null

  visit-Import node/Import -> any:
    return null

  visit-Export node/Export -> any:
    node.exports.do: it.accept this
    return null

  visit-Class node/Class -> any:
    node.static-fields.do: it.accept this
    node.static-functions.do: it.accept this
    node.fields.do: it.accept this
    node.members.do: it.accept this
    return null

  visit-Function node/Function -> any:
    node.parameters.do: it.accept this
    if node.return-type: node.return-type.accept this
    if node.body: node.body.accept this
    return null

  visit-Operator node/Function -> any:
    return visit-Function node

  visit-VarDefinition node/VarDefinition -> any:
    if node.initial: node.initial.accept this
    return null

  // Statements.
  visit-Sequence node/Sequence -> any:
    node.statements.do: it.accept this
    return null

  visit-If node/If -> any:
    node.condition.accept this
    node.then-branch.accept this
    if node.else-branch: node.else-branch.accept this
    return null

  visit-While node/While -> any:
    node.condition.accept this
    node.body.accept this
    return null

  visit-For node/For -> any:
    node.init.accept this
    node.condition.accept this
    node.update.accept this
    node.body.accept this
    return null

  visit-TryFinally node/TryFinally -> any:
    node.body.accept this
    node.handler.accept this
    return null

  visit-Return node/Return -> any:
    if node.value: node.value.accept this
    return null

  visit-Break node/Break -> any:
    if node.value: node.value.accept this
    return null

  visit-Continue node/Continue -> any:
    return null

  visit-Throw node/Throw -> any:
    node.value.accept this
    return null

  visit-ExpressionStatement node/ExpressionStatement -> any:
    node.expression.accept this
    return null

  visit-LocalDefinition node/LocalDefinition -> any:
    node.definition.accept this
    return null

  // Expressions.
  visit-Call node/Call -> any:
    node.target.accept this
    node.arguments.do: it.accept this
    return null

  visit-Index node/Index -> any:
    node.target.accept this
    node.index.accept this
    return null

  visit-IndexAssign node/IndexAssign -> any:
    node.target.accept this
    node.index.accept this
    node.value.accept this
    return null

  visit-IndexSlice node/IndexSlice -> any:
    node.target.accept this
    if node.from: node.from.accept this
    if node.to: node.to.accept this
    return null

  visit-Assign node/Assign -> any:
    node.value.accept this
    return null

  visit-Block node/Block -> any:
    node.parameters.do: it.accept this
    node.body.accept this
    return null

  visit-Lambda node/Lambda -> any:
    node.parameters.do: it.accept this
    node.body.accept this
    return null

  visit-Literal node/Literal -> any:
    return null

  visit-LateInitialized node/LateInitialized -> any:
    return null

  visit-Ref node/Ref -> any:
    return null

  visit-ImportedRef node/ImportedRef -> any:
    return null

  visit-As node/As -> any:
    node.expression.accept this
    return null

  visit-Is node/Is -> any:
    node.expression.accept this
    return null

  visit-Binary node/Binary -> any:
    node.left.accept this
    node.right.accept this
    return null

  visit-Ternary node/Ternary -> any:
    node.condition.accept this
    node.then-value.accept this
    node.else-value.accept this
    return null

  visit-Unary node/Unary -> any:
    node.operand.accept this
    return null

  visit-Named node/Named -> any:
    node.value.accept this
    return null

  visit-StringInterpolation node/StringInterpolation -> any:
    for i := 1; i < node.parts.size; i += 2:
      (node.parts[i] as Expression).accept this
    return null

  visit-ListLiteral node/ListLiteral -> any:
    node.elements.do: (it as Expression).accept this
    return null

  visit-MapLiteral node/MapLiteral -> any:
    for i := 0; i < node.keys.size; i++:
      (node.keys[i] as Expression).accept this
      (node.values[i] as Expression).accept this
    return null

  visit-SetLiteral node/SetLiteral -> any:
    node.elements.do: (it as Expression).accept this
    return null

  visit-Super node/Super -> any:
    return null
