// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/** Verifies that adversarial text still produces analyzable Toit source. */

import expect show *
import host
import host.pipe
import toit-gen

main:
  host.with-tmp-directory "/tmp/toit-gen-render-analyze-": | tmp-dir |
    module := "$tmp-dir/generated.toit"
    parameter := toit-gen.VarDefinition.parameter "value"
    function := toit-gen.Function "escaped" --parameters=[parameter] --return-type=null
    function.toitdoc = ["Literal \$reference, [link], `code`, and */ stay literal."]

    body := toit-gen.Sequence
    body.add (toit-gen.ExpressionStatement (
      toit-gen.Literal "quote=\" slash=\\ dollar=\$ newline=\n control=$(string.from-rune 0x7f)"))
    body.add (toit-gen.ExpressionStatement (
      toit-gen.StringInterpolation ["literal \$reference and ", toit-gen.Ref parameter, "\nend"]))
    function.body = body

    library := toit-gen.Library module
    core-import := library.add-core-import
    core-map := core-import.refer (toit-gen.Class.core "Map")
    shadowing-map := toit-gen.Class "Map" --kind=toit-gen.Class.CLASS
    library.classes.add shadowing-map

    data := toit-gen.VarDefinition.parameter "data" --type=core-map
    qualified := toit-gen.Function "qualified"
        --parameters=[data]
        --return-type=core-map
    qualified-body := toit-gen.Sequence
    qualified-body.add (toit-gen.Statement (toit-gen.As (toit-gen.Ref data) core-map))
    qualified-body.add (toit-gen.Statement (toit-gen.Is (toit-gen.Ref data) core-map))
    qualified-body.ret (toit-gen.Ref data)
    qualified.body = qualified-body

    library.functions.add function
    library.functions.add qualified
    program := toit-gen.Program
    program.libraries.add library
    program.gen

    exit-code := pipe.run-program "toit" "analyze" module
    expect (exit-code == 0) --message="generated adversarial source must analyze"
