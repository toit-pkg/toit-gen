// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import host
import host.directory
import host.file
import system
import toit-gen

main:
  test-replaces-file-and-preserves-permissions
  test-render-failure-does-not-change-files
  test-replacement-failure-cleans-temporary-files

test-replaces-file-and-preserves-permissions:
  host.with-tmp-directory "/tmp/toit-gen-filesystem-": | tmp-dir |
    path := "$tmp-dir/generated.toit"
    file.write-contents "old" --path=path
    expected-permissions := 0b110_100_000
    if system.platform != system.PLATFORM-WINDOWS:
      file.chmod path expected-permissions

    program := toit-gen.Program
    program.libraries.add
        library-with-expression path (toit-gen.Literal "new")
    program.gen

    code := (file.read-contents path).to-string
    expect (code.contains "generated:")
    expect (code.contains "\"new\"")
    if system.platform != system.PLATFORM-WINDOWS:
      expect-equals expected-permissions (file.stat path)[file.ST-MODE]
    expect-directory-entries tmp-dir ["generated.toit"]

test-render-failure-does-not-change-files:
  host.with-tmp-directory "/tmp/toit-gen-render-failure-": | tmp-dir |
    first-path := "$tmp-dir/first.toit"
    second-path := "$tmp-dir/second.toit"
    file.write-contents "unchanged" --path=first-path

    program := toit-gen.Program
    program.libraries.add
        library-with-expression first-path (toit-gen.Literal "replacement")
    program.libraries.add
        library-with-expression second-path (toit-gen.Ref (FailingTarget))

    error := catch: program.gen
    expect (error != null) --message="Expected rendering to fail"
    expect-equals "unchanged" (file.read-contents first-path).to-string
    expect (not file.is-file second-path)
    expect-directory-entries tmp-dir ["first.toit"]

test-replacement-failure-cleans-temporary-files:
  host.with-tmp-directory "/tmp/toit-gen-replace-failure-": | tmp-dir |
    path := "$tmp-dir/generated.toit"
    directory.mkdir path

    program := toit-gen.Program
    program.libraries.add
        library-with-expression path (toit-gen.Literal "replacement")

    error := catch: program.gen
    expect (error != null)
        --message="Expected replacing a directory with a file to fail"
    expect (file.is-directory path)
    expect-directory-entries tmp-dir ["generated.toit"]

expect-directory-entries path/string expected/List -> none:
  actual := []
  host.list-directory path: actual.add it
  actual.sort
  expect-equals expected actual

library-with-expression path/string expression/toit-gen.Expression -> toit-gen.Library:
  body := toit-gen.Sequence
  body.add expression
  function := toit-gen.Function "generated"
      --parameters=[]
      --return-type=null
      body
  library := toit-gen.Library path
  library.functions.add function
  return library

class FailingTarget implements toit-gen.RefTarget:
  name -> string?:
    throw "RENDER_FAILURE"
