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
    library.functions.add function
    program := toit-gen.Program
    program.libraries.add library
    program.gen

    exit-code := pipe.run-program "toit" "analyze" module
    expect (exit-code == 0) --message="generated adversarial source must analyze"
