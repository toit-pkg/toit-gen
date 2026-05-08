// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Library to create Toit code.
*/

import fs
import io
import host.directory
import host.file

import .namer show GlobalNamer MemberNamer LocalNamer Namer
import .toit-gen
import .toit-gen show Lambda
import .visitor show *

class WriteContext_:
  indent-level/int := 0
  writer/io.Writer
  is-new-line_/bool := true

  constructor .writer:

  indent-string -> string:
    return "  " * indent-level

  indent -> none:
    indent-level += 1

  dedent -> none:
    indent-level -= 1
    if indent-level < 0:
      throw "INVALID_STATE"

  write str/string -> none:
    if is-new-line_ and str != "":
      writer.write indent-string
      is-new-line_ = false
    writer.write str

  write-line line/string="" -> none:
    write line
    writer.write "\n"
    is-new-line_ = true

class FixedNamingVisitor extends TraversingVisitor:
  namers/Map
  current-namer/Namer? := null

  constructor .namers:

  visit-Program node/Program -> any:
    node.libraries.do: | library/Library |
      global-namer := namers.get library --init=: GlobalNamer
      current-namer = global-namer
      library.accept this
      current-namer = null
    return null

  visit-Class node/Class -> any:
    old := current-namer
    if node.name: (old as GlobalNamer).reserve node.name
    member-namer := namers.get node --init=: (old as GlobalNamer).new-member-namer
    current-namer = member-namer
    super node
    current-namer = old
    return null

  visit-Function node/Function -> any:
    old := current-namer
    if node.name:
      if old is MemberNamer: (old as MemberNamer).reserve node.name --check=false --deep=true
      else if old is GlobalNamer: (old as GlobalNamer).reserve node.name --check=false
    local-namer := namers.get node --init=:
      old is MemberNamer ? (old as MemberNamer).new-local-namer : (old as GlobalNamer).new-local-namer
    current-namer = local-namer
    super node
    current-namer = old
    return null

  visit-VarDefinition node/VarDefinition -> any:
    if node.name:
      if current-namer is LocalNamer:
        (current-namer as LocalNamer).reserve node.name --deep=true
      else if current-namer is MemberNamer:
        (current-namer as MemberNamer).reserve node.name --check=false --deep=true
      else if current-namer is GlobalNamer:
        (current-namer as GlobalNamer).reserve node.name
    super node
    return null

class LocalNamingVisitor extends TraversingVisitor:
  namers/Map
  current-namer/Namer? := null

  constructor .namers:

  visit-Program node/Program -> any:
    node.libraries.do: | library/Library |
      current-namer = namers[library]
      library.accept this
      current-namer = null
    return null

  visit-Class node/Class -> any:
    old := current-namer
    current-namer = namers[node]
    super node
    current-namer = old
    return null

  visit-Function node/Function -> any:
    old := current-namer
    current-namer = namers[node]
    super node
    current-namer = old
    return null

  visit-VarDefinition node/VarDefinition -> any:
    if not node.name and current-namer is LocalNamer:
      node.name = (current-namer as LocalNamer).use-local node.preferred-name
    super node
    return null

class UnnamedParamNamingVisitor extends TraversingVisitor:
  namers/Map
  current-namer/Namer? := null

  constructor .namers:

  visit-Program node/Program -> any:
    node.libraries.do: | library/Library |
      current-namer = namers[library]
      library.accept this
      current-namer = null
    return null

  visit-Class node/Class -> any:
    old := current-namer
    current-namer = namers[node]
    super node
    current-namer = old
    return null

  visit-Function node/Function -> any:
    old := current-namer
    current-namer = namers[node]
    super node
    current-namer = old
    return null

  visit-VarDefinition node/VarDefinition -> any:
    if not node.name and current-namer is LocalNamer and not node.is-block and not node.initial and not node.is-named:
      outer := (current-namer as LocalNamer).outer-namer
      if outer is MemberNamer:
        node.name = (outer as MemberNamer).use-member node.preferred-name
      else if outer is GlobalNamer:
        node.name = (outer as GlobalNamer).use-global node.preferred-name
    super node
    return null


class GeneratingVisitor implements NodeVisitor:
  context/WriteContext_
  omit-trailing-newline_/bool := false
  current-class_/Class? := null

  constructor .context:

  needs-parens_ node/Expression -> bool:
    if node is Call:
      c := node as Call
      if not c.arguments.is-empty: return true
      if c.target is Ref:
        target-def := (c.target as Ref).target
        if target-def is Class: return true
        if target-def is Function and (target-def as Function).is-constructor: return true
      return false
    if node is Binary: return true
    if node is Unary: return true
    if node is As: return true
    if node is Is: return true
    return false

  expr_ node/Expression -> none:
    node.accept this

  visit-Program node/Program -> any:
    unreachable

  visit-Operator node/Function -> any:
    return visit-Function node

  visit-Library node/Library -> any:
    write-toitdoc_ node.toitdoc
    node.imports.do: | imp | if not imp.refs.is-empty: imp.accept this
    if not node.imports.is-empty: context.write-line ""
    node.exports.do: | exp | exp.accept this
    if not node.exports.is-empty: context.write-line ""
    node.globals.do: | glob | glob.accept this
    node.classes.do: | cls | cls.accept this
    node.functions.do: | fun | fun.accept this
    return null

  visit-Import node/Import -> any:
    line := "import "
    if node.is-relative: line += "."
    line += node.segments.join "."
    if node.prefix:
      line += " as $(node.prefix)"

    if node.show-all:
      line += " show *"
    else if not node.refs.is-empty:
      line += " show "
      ref-name-set := {}
      node.refs.do: | ref/ImportedRef | ref-name-set.add ref.target.name
      line += (ref-name-set.to-list).join " "
    context.write-line line
    return null

  visit-Export node/Export -> any:
    line := "export "
    ref-names := node.exports.map: | ref/Ref | ref.target.name
    line += ref-names.join " "
    context.write-line line
    return null

  visit-Class node/Class -> any:
    old-class := current-class_
    current-class_ = node
    write-toitdoc_ node.toitdoc
    line := ""
    if node.is-abstract: line += "abstract "
    if node.kind == Class.INTERFACE: line += "interface"
    else if node.kind == Class.MIXIN: line += "mixin"
    else: line += "class"
    line += " $node.name"
    if node.super-class:
      line += " extends $(node.super-class.target.name)"
    if not node.interfaces.is-empty:
      line += " implements"
      node.interfaces.do: | ref/Ref |
        line += " $ref.target.name"
    if not node.mixins.is-empty:
      line += " with"
      node.mixins.do: | ref/Ref |
        line += " $ref.target.name"
    line += ":"
    context.write-line line
    context.indent

    node.fields.do: | field/VarDefinition |
      write-toitdoc_ field.toitdoc
      context.write field.name
      if field.type:
        context.write "/$(field.type.target.name)"
        if field.is-nullable: context.write "?"
        if field.initial:
          if field.is-final: context.write " ::= "
          else: context.write " := "
          expr_ field.initial
        else:
          if not field.is-final: context.write " := ?"
      else:
        if field.initial:
          if field.is-final: context.write " ::= "
          else: context.write " := "
          expr_ field.initial
        else:
          if not field.is-final: context.write " := ?"
          else: context.write " ::= ?"
      context.write-line ""

    node.members.do: | member/Function |
      if member.is-constructor: context.write-line ""
      member.accept this

    context.dedent
    context.write-line ""
    current-class_ = old-class
    return null

  visit-Function node/Function -> any:
    write-toitdoc_ node.toitdoc
    line := ""
    if node.is-abstract: line += "abstract "
    if node.is-constructor and node.name != "constructor":
      // Named constructor (e.g., constructor.from-json).
      line += "constructor.$node.name"
    else:
      line += "$node.name"
    node.parameters.do: | param/VarDefinition |
      param-str := param.name
      if param.is-named: param-str = "--$param-str"
      line += " $param-str"

    if not node.is-constructor:
      if node.return-type:
        line += " -> $(node.return-type.target.name)"

    if not node.is-abstract:
      line += ":"

    context.write-line line
    if node.body:
      context.indent
      node.body.accept this
      context.dedent
    context.write-line ""
    return null

  visit-VarDefinition node/VarDefinition -> any:
    return null

  visit-Sequence node/Sequence -> any:
    old-omit := omit-trailing-newline_
    for i := 0; i < node.statements.size; i++:
      omit-trailing-newline_ = old-omit and i == node.statements.size - 1
      node.statements[i].accept this
    omit-trailing-newline_ = old-omit
    return null

  visit-If node/If -> any:
    context.write "if "
    // We use `write-arg_` to get parenthesis around the condition if it
    // isn't simple. This is over-conservative but handles the case where
    // the condition is a call with a block argument.
    write-arg_ node.condition
    context.write-line ":"
    context.indent
    node.then-branch.accept this
    context.dedent
    if node.else-branch:
      context.write-line "else:"
      context.indent
      node.else-branch.accept this
      context.dedent
    return null

  visit-Return node/Return -> any:
    if node.value:
      context.write "return "
      expr_ node.value
    else:
      context.write "return"
    if not omit-trailing-newline_ and not context.is-new-line_: context.write-line ""
    return null

  visit-ExpressionStatement node/ExpressionStatement -> any:
    expr_ node.expression
    if not omit-trailing-newline_ and not context.is-new-line_: context.write-line ""
    return null

  visit-LocalDefinition node/LocalDefinition -> any:
    def := node.definition
    context.write "$def.name := "
    expr_ def.initial
    if not omit-trailing-newline_ and not context.is-new-line_: context.write-line ""
    return null

  visit-Break node/Break -> any:
    if node.value:
      context.write "break "
      write-arg_ node.value
    else:
      context.write "break"
    if not omit-trailing-newline_ and not context.is-new-line_: context.write-line ""
    return null

  visit-Continue node/Continue -> any:
    context.write "continue"
    if not omit-trailing-newline_ and not context.is-new-line_: context.write-line ""
    return null

  visit-While node/While -> any:
    context.write "while "
    write-arg_ node.condition
    context.write-line ":"
    context.indent
    node.body.accept this
    context.dedent
    return null

  visit-For node/For -> any:
    old-omit := omit-trailing-newline_
    omit-trailing-newline_ = true
    context.write "for "
    expr_ node.init
    context.write "; "
    expr_ node.condition
    context.write "; "
    expr_ node.update
    omit-trailing-newline_ = old-omit
    context.write-line ":"
    context.indent
    node.body.accept this
    context.dedent
    return null

  visit-TryFinally node/TryFinally -> any:
    context.write-line "try:"
    context.indent
    node.body.accept this
    context.dedent
    context.write-line "finally:"
    context.indent
    node.handler.accept this
    context.dedent
    return null

  visit-Throw node/Throw -> any:
    context.write "throw "
    expr_ node.value
    context.write-line ""
    return null

  visit-Call node/Call -> any:
    target-parens := needs-parens_ node.target
    if node.method-name and (node.target is Call and not (node.target as Call).method-name and (node.target as Call).arguments.is-empty):
      target-parens = true

    if target-parens: context.write "("
    expr_ node.target
    if target-parens: context.write ")"
    if node.method-name: context.write ".$(node.method-name)"

    if node.arguments.is-empty: return null

    blocks := []
    normal-args := []
    node.arguments.do: | arg |
      if arg is Block: blocks.add arg
      else if arg is Named and (arg as Named).value is Block: blocks.add arg
      else: normal-args.add arg

    multi-block := blocks.size > 1
    if not normal-args.is-empty:
      if multi-block:
        // In multi-block mode, put all args on continuation lines.
        normal-args.do: | arg |
          context.write "\n$(context.indent-string)    "
          write-arg_ arg
      else:
        has-named := normal-args.any: it is Named
        if normal-args.size > 2 and has-named:
          context.write " "
          write-arg_ normal-args[0]
          for i := 1; i < normal-args.size; i++:
            context.write "\n$(context.indent-string)    "
            write-arg_ normal-args[i]
        else:
          normal-args.do: | arg |
            context.write " "
            write-arg_ arg

    for i := 0; i < blocks.size; i++:
      blk := blocks[i]
      if multi-block:
        // Each block on its own line, indented by 4 from the call.
        context.write "\n$(context.indent-string)    "
      if blk is Named:
        n-blk := blk as Named
        if multi-block or i > 0:
          context.write "--$(n-blk.parameter.name)="
        else:
          context.write " --$(n-blk.parameter.name)="
        blk = n-blk.value

      b := blk as Block
      context.write ":"
      if not b.parameters.is-empty:
        p-names := b.parameters.map: it.name
        context.write " | $(p-names.join " ") |"

      if multi-block:
        // Body at +4 from block header. Always omit trailing newline
        // to prevent blank lines between blocks.
        context.indent-level += 2
        stream-block-body_ b.body true
        context.indent-level -= 2
      else:
        is-last := i == blocks.size - 1
        stream-block-body_ b.body is-last

    return null

  visit-Index node/Index -> any:
    if needs-parens_ node.target: context.write "("
    expr_ node.target
    if needs-parens_ node.target: context.write ")"
    context.write "["
    expr_ node.index
    context.write "]"
    return null

  visit-IndexSlice node/IndexSlice -> any:
    if needs-parens_ node.target: context.write "("
    expr_ node.target
    if needs-parens_ node.target: context.write ")"
    context.write "["
    if node.from: expr_ node.from
    context.write ".."
    if node.to: expr_ node.to
    context.write "]"
    return null

  visit-Assign node/Assign -> any:
    context.write "$node.target.name = "
    expr_ node.value
    return null

  visit-Block node/Block -> any:
    unreachable

  visit-Lambda node/Lambda -> any:
    context.write "::"
    if not node.parameters.is-empty:
      p-names := node.parameters.map: it.name
      context.write " | $(p-names.join " ") |"

    stream-block-body_ node.body true
    return null

  visit-Literal node/Literal -> any:
    v := node.value
    if v is string: context.write "\"$v\""
    else if v is int or v is float or v is bool: context.write "$v"
    else if v == null: context.write "null"
    else if v is List and v.is-empty: context.write "[]"
    else if v is Map and v.is-empty: context.write "{:}"
    else: unreachable
    return null

  visit-LateInitialized node/LateInitialized -> any:
    context.write "?"
    return null

  visit-Ref node/Ref -> any:
    context.write node.target.name
    return null

  visit-ImportedRef node/ImportedRef -> any:
    if node.imp.prefix: context.write "$node.imp.prefix.$node.target.name"
    else: context.write node.target.name
    return null

  visit-As node/As -> any:
    if needs-parens_ node.expression: context.write "("
    expr_ node.expression
    if needs-parens_ node.expression: context.write ")"
    context.write " as $node.type.name"
    return null

  visit-Is node/Is -> any:
    if needs-parens_ node.expression: context.write "("
    expr_ node.expression
    if needs-parens_ node.expression: context.write ")"
    context.write " is $node.type.name"
    return null

  visit-Binary node/Binary -> any:
    write-arg_ node.left
    context.write " $node.op "
    write-arg_ node.right
    return null

  visit-Named node/Named -> any:
    context.write "--$node.parameter.name="
    expr_ node.value
    return null

  visit-Unary node/Unary -> any:
    if node.op == "not":
      context.write "not "
      write-arg_ node.operand
    else:
      context.write node.op
      if needs-parens_ node.operand:
        context.write "("
        expr_ node.operand
        context.write ")"
      else:
        expr_ node.operand
    return null

  visit-StringInterpolation node/StringInterpolation -> any:
    context.write "\""
    for i := 0; i < node.parts.size; i++:
      if i % 2 == 0:
        context.write node.parts[i]
      else:
        part := node.parts[i]
        if part is Ref:
          context.write "\$$(((part as Ref).target.name))"
        else:
          context.write "\$("
          expr_ part
          context.write ")"
    context.write "\""
    return null

  visit-ListLiteral node/ListLiteral -> any:
    context.write "["
    for i := 0; i < node.elements.size; i++:
      if i > 0: context.write ", "
      expr_ node.elements[i]
    context.write "]"
    return null

  visit-MapLiteral node/MapLiteral -> any:
    context.write "{"
    for i := 0; i < node.keys.size; i++:
      if i > 0: context.write ", "
      expr_ node.keys[i]
      context.write ": "
      expr_ node.values[i]
    context.write "}"
    return null

  visit-SetLiteral node/SetLiteral -> any:
    context.write "{"
    for i := 0; i < node.elements.size; i++:
      if i > 0: context.write ", "
      expr_ node.elements[i]
    context.write "}"
    return null

  visit-Super node/Super -> any:
    context.write "super"
    return null

  write-arg_ arg/Expression -> none:
    if needs-parens_ arg:
      context.write "("
      expr_ arg
      context.write ")"
    else:
      expr_ arg

  stream-block-body_ body/Statement omit/bool -> none:
    context.write-line ""
    context.indent
    old-omit := omit-trailing-newline_
    omit-trailing-newline_ = omit
    body.accept this
    omit-trailing-newline_ = old-omit
    context.dedent

  write-toitdoc_ toitdoc/List? -> none:
    if not toitdoc: return
    parts := []
    toitdoc.do: | segment |
      if segment is string:
        parts.add segment
      else if segment is ToitdocNameRef:
        ref := segment as ToitdocNameRef
        if ref.holder and (not current-class_ or not (identical ref.holder current-class_)):
          parts.add "\$$(ref.holder.name).$(ref.target.name)"
        else:
          parts.add "\$$(ref.target.name)"
      else if segment is ToitdocExactRef:
        ref := segment as ToitdocExactRef
        param-parts := ref.target.parameters.map: | p/VarDefinition |
          if p.is-block: "[$p.name]"
          else if p.is-named: "--$p.name"
          else: p.name
        params := param-parts.join " "
        qualified/string := ?
        if ref.holder and (not current-class_ or not (identical ref.holder current-class_)):
          qualified = "$(ref.holder.name).$(ref.target.name)"
        else:
          qualified = ref.target.name
        if params.is-empty:
          parts.add "\$($qualified)"
        else:
          parts.add "\$($qualified $params)"
      else if segment is ToitdocSuperRef:
        parts.add "\$super"
    text := parts.join ""
    lines := text.split "\n"
    if lines.size == 1:
      context.write-line "/** $text */"
    else:
      context.write-line "/**"
      lines.do: context.write-line it
      context.write-line "*/"
