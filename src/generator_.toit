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
      // Name through the function's own scope: $Namer.is-free chains
      //   through the member and global namers (whose names are all
      //   assigned by this phase), so the parameter cannot shadow them,
      //   while sibling functions remain free to reuse the same name.
      node.name = (current-namer as LocalNamer).use-local node.preferred-name
    super node
    return null


class GeneratingVisitor implements NodeVisitor:
  context/WriteContext_
  omit-trailing-newline_/bool := false
  current-class_/Class? := null
  in-static_/bool := false
  // > 0 while rendering inside parentheses. Blocks must then render
  //   inline: streaming a block body onto indented lines would leave the
  //   closing parenthesis after the block, which the parser rejects.
  parenthesized-depth_/int := 0

  constructor .context:

  /// Writes $str to the underlying $context.
  write str/string -> none:
    context.write str

  /// Writes $line followed by a newline to the underlying $context.
  write-line line/string="" -> none:
    context.write-line line

  /**
  Runs $block with $in-static_ set, restoring it afterwards.

  Used while rendering a class's static members so that nested renderers
    (e.g. $write-field_ and $visit-Function) emit the `static` keyword.
  */
  in-static [block] -> none:
    old := in-static_
    in-static_ = true
    try:
      block.call
    finally:
      in-static_ = old

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
    if node is Ternary: return true
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
    if not node.imports.is-empty: write-line
    node.exports.do: | exp | exp.accept this
    if not node.exports.is-empty: write-line
    node.globals.do: | glob | glob.accept this
    node.classes.do: | cls | cls.accept this
    node.functions.do: | fun | fun.accept this
    return null

  visit-Import node/Import -> any:
    line := "import "
    if node.is-relative: line += "."
    line += node.segments.join "."
    if node.uses-prefix:
      // A prefix is in scope, so references qualify through it. A package
      //   import binds its last segment implicitly, so `as` is only needed
      //   when the prefix differs. A relative import binds no implicit
      //   prefix, so it always needs an explicit `as`.
      if node.is-relative or node.prefix != node.segments.last:
        line += " as $node.prefix"
    else if node.show-all:
      // `show *` brings the names into scope directly, which removes the
      //   prefix. To get both a qualified prefix and unqualified names, add
      //   two separate imports of the same target.
      line += " show *"
    write-line line
    return null

  visit-Export node/Export -> any:
    line := "export "
    ref-names := node.exports.map: | ref/Ref | ref.target.name
    line += ref-names.join " "
    write-line line
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
      line += " extends $(ref-name_ node.super-class)"
    if not node.interfaces.is-empty:
      line += " implements"
      node.interfaces.do: | ref/Ref |
        line += " $(ref-name_ ref)"
    if not node.mixins.is-empty:
      line += " with"
      node.mixins.do: | ref/Ref |
        line += " $(ref-name_ ref)"
    line += ":"
    write-line line
    context.indent

    node.fields.do: | field/VarDefinition |
      write-field_ field

    node.static-fields.do: | field/VarDefinition |
      in-static: write-field_ field

    node.members.do: | member/Function |
      if member.is-constructor: write-line
      member.accept this

    node.static-functions.do: | fun/Function |
      in-static: fun.accept this

    context.dedent
    write-line
    current-class_ = old-class
    return null

  write-field_ field/VarDefinition -> none:
    write-toitdoc_ field.toitdoc
    if in-static_: write "static "
    write-var-declaration_ field
    write-line

  /**
  Renders a $VarDefinition in declaration position: its name, an optional
    `/Type` (with a trailing `?` when nullable), and an initializer.

  A field or variable without an initializer renders the late-initialization
    form: `:= ?` when mutable, `::= ?` for an untyped final field. A typed
    final field is left uninitialized, to be assigned in a constructor.
  */
  write-var-declaration_ def/VarDefinition -> none:
    write def.name
    if def.type:
      write "/"
      def.type.accept this
      if def.is-nullable: write "?"
    if def.initial:
      write (def.is-final ? " ::= " : " := ")
      expr_ def.initial
    else if not def.is-final:
      write " := ?"
    else if not def.type:
      write " ::= ?"

  visit-Function node/Function -> any:
    write-toitdoc_ node.toitdoc
    // Interface members in Toit are implicitly abstract: no `abstract`
    // keyword, no body, no colon (for non-constructor signatures). Factory
    // constructors and static methods on an interface still get a body and
    // are emitted normally.
    is-interface-member := current-class_ != null
        and current-class_.kind == Class.INTERFACE
        and not node.is-constructor
        and not in-static_
    prefix := ""
    if node.is-abstract and not is-interface-member: prefix += "abstract "
    if in-static_: prefix += "static "
    if node.is-constructor and node.name != "constructor":
      // Named constructor (e.g., constructor.from-json).
      prefix += "constructor.$node.name"
    else:
      prefix += "$node.name"
    write prefix

    node.parameters.do: | param/VarDefinition |
      write " "
      write-param_ param

    if not node.is-constructor:
      if node.return-type:
        write " -> "
        node.return-type.accept this

    if not node.is-abstract and not is-interface-member:
      write ":"

    write-line
    if node.body:
      context.indent
      node.body.accept this
      context.dedent
    write-line
    return null

  /**
  Renders a $VarDefinition in parameter position.

  Handles named (`--name`), typed (`name/Type`), nullable (`name/Type?`),
    and defaulted (`name=initial`) parameters.
  */
  write-param_ param/VarDefinition -> none:
    if param.is-named: write "--"
    write param.name
    if param.type:
      write "/"
      param.type.accept this
      if param.is-nullable: write "?"
    if param.initial:
      write "="
      expr_ param.initial

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
    write "if "
    // We use `write-arg_` to get parenthesis around the condition if it
    // isn't simple. This is over-conservative but handles the case where
    // the condition is a call with a block argument.
    write-arg_ node.condition
    write-line ":"
    context.indent
    node.then-branch.accept this
    context.dedent
    if node.else-branch:
      write-line "else:"
      context.indent
      node.else-branch.accept this
      context.dedent
    return null

  visit-Return node/Return -> any:
    if node.value:
      write "return "
      expr_ node.value
    else:
      write "return"
    if not omit-trailing-newline_ and not context.is-new-line_: write-line
    return null

  visit-ExpressionStatement node/ExpressionStatement -> any:
    expr_ node.expression
    if not omit-trailing-newline_ and not context.is-new-line_: write-line
    return null

  visit-LocalDefinition node/LocalDefinition -> any:
    write-var-declaration_ node.definition
    if not omit-trailing-newline_ and not context.is-new-line_: write-line
    return null

  visit-Break node/Break -> any:
    if node.value:
      write "break "
      write-arg_ node.value
    else:
      write "break"
    if not omit-trailing-newline_ and not context.is-new-line_: write-line
    return null

  visit-Continue node/Continue -> any:
    write "continue"
    if not omit-trailing-newline_ and not context.is-new-line_: write-line
    return null

  visit-While node/While -> any:
    write "while "
    write-arg_ node.condition
    write-line ":"
    context.indent
    node.body.accept this
    context.dedent
    return null

  visit-For node/For -> any:
    old-omit := omit-trailing-newline_
    omit-trailing-newline_ = true
    write "for "
    expr_ node.init
    write "; "
    expr_ node.condition
    write "; "
    expr_ node.update
    omit-trailing-newline_ = old-omit
    write-line ":"
    context.indent
    node.body.accept this
    context.dedent
    return null

  visit-TryFinally node/TryFinally -> any:
    write-line "try:"
    context.indent
    node.body.accept this
    context.dedent
    write-line "finally:"
    context.indent
    node.handler.accept this
    context.dedent
    return null

  visit-Throw node/Throw -> any:
    write "throw "
    expr_ node.value
    write-line
    return null

  visit-Call node/Call -> any:
    target-parens := needs-parens_ node.target
    if node.method-name and (node.target is Call and not (node.target as Call).method-name and (node.target as Call).arguments.is-empty):
      target-parens = true

    // Note: a parenthesized *target* keeps streaming its blocks — the
    //   closing parenthesis hugs the last body line (`return []).add x`),
    //   which the parser accepts. Only parenthesized *arguments* need
    //   inline blocks; see $write-parenthesized_.
    if target-parens: write "("
    expr_ node.target
    if target-parens: write ")"
    if node.method-name: write ".$(node.method-name)"

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
          write "\n$(context.indent-string)    "
          write-call-arg_ arg
      else:
        has-named := normal-args.any: it is Named
        if normal-args.size > 2 and has-named:
          write " "
          write-call-arg_ normal-args[0]
          for i := 1; i < normal-args.size; i++:
            write "\n$(context.indent-string)    "
            write-call-arg_ normal-args[i]
        else:
          normal-args.do: | arg |
            write " "
            write-call-arg_ arg

    inline-blocks := parenthesized-depth_ > 0
    if inline-blocks and multi-block:
      throw "Cannot render a call with multiple blocks inside a parenthesized argument"

    for i := 0; i < blocks.size; i++:
      blk := blocks[i]
      if multi-block:
        // Each block on its own line, indented by 4 from the call.
        write "\n$(context.indent-string)    "
      if blk is Named:
        n-blk := blk as Named
        if multi-block or i > 0:
          write "--$(n-blk.parameter.name)="
        else:
          write " --$(n-blk.parameter.name)="
        blk = n-blk.value

      b := blk as Block
      write ":"
      if not b.parameters.is-empty:
        p-names := b.parameters.map: it.name
        write " | $(p-names.join " ") |"

      if inline-blocks:
        single := inline-block-expression_ b.body
        if single:
          // A single-expression body stays on the same line.
          write " "
          expr_ single
        else:
          // A multi-statement body streams, but must be indented deeper
          // than the argument continuation lines (statement indent + 4)
          // or the parser detaches it from the block header.
          context.indent-level += 2
          stream-block-body_ b.body true
          context.indent-level -= 2
      else if multi-block:
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
    if needs-parens_ node.target: write "("
    expr_ node.target
    if needs-parens_ node.target: write ")"
    write "["
    expr_ node.index
    write "]"
    return null

  visit-IndexSlice node/IndexSlice -> any:
    if needs-parens_ node.target: write "("
    expr_ node.target
    if needs-parens_ node.target: write ")"
    write "["
    if node.from: expr_ node.from
    write ".."
    if node.to: expr_ node.to
    write "]"
    return null

  visit-Assign node/Assign -> any:
    write "$node.target.name = "
    expr_ node.value
    return null

  visit-Block node/Block -> any:
    unreachable

  visit-Lambda node/Lambda -> any:
    write "::"
    if not node.parameters.is-empty:
      p-names := node.parameters.map: it.name
      write " | $(p-names.join " ") |"

    stream-block-body_ node.body true
    return null

  visit-Literal node/Literal -> any:
    v := node.value
    if v is string: write "\"$v\""
    else if v is int or v is float or v is bool: write "$v"
    else if v == null: write "null"
    else if v is List and v.is-empty: write "[]"
    else if v is Map and v.is-empty: write "{:}"
    else: unreachable
    return null

  visit-LateInitialized node/LateInitialized -> any:
    write "?"
    return null

  /**
  The source name of $ref, including the import prefix for an
    $ImportedRef through a prefixed import.
  */
  ref-name_ ref/Ref -> string:
    if ref is ImportedRef:
      imported := ref as ImportedRef
      if imported.imp.uses-prefix:
        return "$imported.imp.prefix.$imported.target.name"
    return ref.target.name

  visit-Ref node/Ref -> any:
    write node.target.name
    return null

  visit-ImportedRef node/ImportedRef -> any:
    if node.imp.uses-prefix:
      write "$node.imp.prefix.$node.target.name"
    else:
      write node.target.name
    return null

  visit-As node/As -> any:
    if needs-parens_ node.expression: write "("
    expr_ node.expression
    if needs-parens_ node.expression: write ")"
    write " as $node.type.name"
    return null

  visit-Is node/Is -> any:
    if needs-parens_ node.expression: write "("
    expr_ node.expression
    if needs-parens_ node.expression: write ")"
    write " is $node.type.name"
    return null

  visit-Binary node/Binary -> any:
    write-arg_ node.left
    write " $node.op "
    write-arg_ node.right
    return null

  visit-Ternary node/Ternary -> any:
    write-arg_ node.condition
    write " ? "
    write-arg_ node.then-value
    write " : "
    write-arg_ node.else-value
    return null

  visit-Named node/Named -> any:
    // `--flag=true` is equivalent to `--flag` in Toit, and `--flag=false` to
    // `--no-flag`. Emit the shorthand.
    if node.value is Literal:
      literal-value := (node.value as Literal).value
      if literal-value == true:
        write "--$node.parameter.name"
        return null
      if literal-value == false:
        write "--no-$node.parameter.name"
        return null
    write "--$node.parameter.name="
    expr_ node.value
    return null

  visit-Unary node/Unary -> any:
    if node.op == "not":
      write "not "
      write-arg_ node.operand
    else:
      write node.op
      if needs-parens_ node.operand:
        write "("
        expr_ node.operand
        write ")"
      else:
        expr_ node.operand
    return null

  visit-StringInterpolation node/StringInterpolation -> any:
    write "\""
    for i := 0; i < node.parts.size; i++:
      if i % 2 == 0:
        write node.parts[i]
      else:
        part := node.parts[i]
        if part is Ref:
          write "\$$(((part as Ref).target.name))"
        else:
          write "\$("
          expr_ part
          write ")"
    write "\""
    return null

  visit-ListLiteral node/ListLiteral -> any:
    write "["
    for i := 0; i < node.elements.size; i++:
      if i > 0: write ", "
      expr_ node.elements[i]
    write "]"
    return null

  visit-MapLiteral node/MapLiteral -> any:
    write "{"
    for i := 0; i < node.keys.size; i++:
      if i > 0: write ", "
      expr_ node.keys[i]
      write ": "
      expr_ node.values[i]
    write "}"
    return null

  visit-SetLiteral node/SetLiteral -> any:
    write "{"
    for i := 0; i < node.elements.size; i++:
      if i > 0: write ", "
      expr_ node.elements[i]
    write "}"
    return null

  visit-Super node/Super -> any:
    write "super"
    return null

  write-arg_ arg/Expression -> none:
    if needs-parens_ arg:
      write "("
      expr_ arg
      write ")"
    else:
      expr_ arg

  /**
  Writes a call argument, forcing blocks inside parentheses to render
    inline.

  Unlike an if-condition or a parenthesized call target — where a
    streamed block body keeps a parseable indentation — a call argument
    can sit on a continuation line, where the streamed body would be
    indented left of its own header and the parser rejects it.
  */
  write-call-arg_ arg/Expression -> none:
    if needs-parens_ arg:
      write-parenthesized_ arg
    else:
      expr_ arg

  /// Writes $node wrapped in parentheses; see $parenthesized-depth_.
  write-parenthesized_ node/Expression -> none:
    write "("
    parenthesized-depth_++
    expr_ node
    parenthesized-depth_--
    write ")"

  /**
  The single expression of a block body that can be rendered inline, or
    null for a multi-statement body.
  */
  inline-block-expression_ body/Statement -> Expression?:
    if body is ExpressionStatement: return (body as ExpressionStatement).expression
    if body is Sequence:
      seq := body as Sequence
      if seq.statements.size == 1:
        return inline-block-expression_ seq.statements[0]
    return null

  stream-block-body_ body/Statement omit/bool -> none:
    write-line
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
      write-line "/** $text */"
    else:
      write-line "/**"
      lines.do: write-line it
      write-line "*/"
