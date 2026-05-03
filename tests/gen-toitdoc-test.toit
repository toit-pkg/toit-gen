// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import toit-gen

main:
  test-toitdocs
  test-toitdoc-class
  test-toitdoc-field
  test-toitdoc-function
  test-toitdoc-member-params
  test-toitdoc-exact-named-block
  test-toitdoc-member-no-shadow-global
  test-toitdoc-ref-global-from-class
  test-toitdoc-param-shadows-global
  test-toitdoc-param-shadows-member

test-toitdocs:
  lib := toit-gen.Library "test-toitdocs.toit"
  lib.toitdoc = ["Some lib comment."]

  // Class A with two overloaded foo methods.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  param-x := toit-gen.VarDefinition.parameter "x"
  param-x.name = "x"
  foo1 := toit-gen.Function "foo" --parameters=[param-x] --return-type=null

  param-x2 := toit-gen.VarDefinition.parameter "x"
  param-x2.name = "x"
  param-y := toit-gen.VarDefinition.parameter "y"
  param-y.name = "y"
  foo2 := toit-gen.Function "foo" --parameters=[param-x2, param-y] --return-type=null

  cls.members.add foo1
  cls.members.add foo2
  lib.classes.add cls

  // Top-level function bar with a toitdoc that references A.foo.
  bar := toit-gen.Function "bar" --parameters=[] --return-type=null
  bar.toitdoc = [
    "A toitdoc that references:\n",
    "- all ", toit-gen.ToitdocNameRef foo1 --holder=cls, " (name-based)\n",
    "- the specific ", toit-gen.ToitdocExactRef foo2 --holder=cls, " member with 2 arguments.",
  ]
  lib.functions.add bar

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdocs.toit"]

  expected := """
    /** Some lib comment. */
    class A:
      foo x:

      foo x y:


    /**
    A toitdoc that references:
    - all \$A.foo (name-based)
    - the specific \$(A.foo x y) member with 2 arguments.
    */
    bar:"""
  expect-equals expected code.trim


  // Test scope-aware ref: inside class B, holder should be omitted.
  cls2 := toit-gen.Class "B" --kind=toit-gen.Class.CLASS
  param-z := toit-gen.VarDefinition.parameter "z"
  param-z.name = "z"
  baz := toit-gen.Function "baz" --parameters=[param-z] --return-type=null
  baz.toitdoc = [
    "See ", toit-gen.ToitdocNameRef baz,
    " and ", toit-gen.ToitdocExactRef baz,
    " and ", toit-gen.ToitdocSuperRef, ".",
  ]
  cls2.members.add baz

  lib2 := toit-gen.Library "test-toitdocs2.toit"
  lib2.classes.add cls2

  program2 := toit-gen.Program
  program2.libraries.add lib2

  generated2 := program2.gen --in-memory
  code2 := generated2["test-toitdocs2.toit"]

  expected2 := """
    class B:
      /** See \$baz and \$(baz z) and \$super. */
      baz z:"""
  expect-equals expected2 code2.trim

test-toitdoc-class:
  // Test toitdoc on a class.
  lib := toit-gen.Library "test-toitdoc-class.toit"
  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS

  p := toit-gen.VarDefinition.parameter "v"
  p.name = "v"
  member := toit-gen.Function "do-something" --parameters=[p] --return-type=null
  cls.members.add member

  // Class toitdoc references its own member (scope-aware: no qualifier).
  cls.toitdoc = [
    "A class that can ", toit-gen.ToitdocNameRef member, ".",
  ]
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-class.toit"]

  expected := """
    /** A class that can \$do-something. */
    class MyClass:
      do-something v:"""
  expect-equals expected code.trim

test-toitdoc-field:
  // Test toitdoc on a field.
  lib := toit-gen.Library "test-toitdoc-field.toit"
  cls := toit-gen.Class "Config" --kind=toit-gen.Class.CLASS

  field := toit-gen.VarDefinition.field "timeout"
      --type=(toit-gen.Ref (toit-gen.Class.core "int"))
      --initial=(toit-gen.Literal 30)
      --is-final=false
  field.toitdoc = ["The timeout in seconds."]
  cls.fields.add field
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-field.toit"]

  expected := """
    class Config:
      /** The timeout in seconds. */
      timeout/int := 30"""
  expect-equals expected code.trim

test-toitdoc-function:
  // Test toitdoc on a top-level function referencing its own parameter.
  lib := toit-gen.Library "test-toitdoc-function.toit"

  p1 := toit-gen.VarDefinition.parameter "host"
  p1.name = "host"
  p2 := toit-gen.VarDefinition.parameter "port"
  p2.name = "port"
  fun := toit-gen.Function "connect" --parameters=[p1, p2] --return-type=null
  fun.toitdoc = [
    "Connects to the given ", toit-gen.ToitdocNameRef p1,
    " on ", toit-gen.ToitdocNameRef p2, ".",
  ]
  lib.functions.add fun

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-function.toit"]

  expected := """
    /** Connects to the given \$host on \$port. */
    connect host port:"""
  expect-equals expected code.trim

test-toitdoc-member-params:
  // Test toitdoc on a member function referencing its own parameters
  // (including named and block params).
  lib := toit-gen.Library "test-toitdoc-member-params.toit"
  cls := toit-gen.Class "Client" --kind=toit-gen.Class.CLASS

  p-url := toit-gen.VarDefinition.parameter "url"
  p-url.name = "url"
  p-timeout := toit-gen.VarDefinition.parameter "timeout" --is-named=true
  p-timeout.name = "timeout"
  p-callback := toit-gen.VarDefinition.parameter "callback" --is-block=true
  p-callback.name = "callback"

  fetch := toit-gen.Function "fetch" --parameters=[p-url, p-timeout, p-callback] --return-type=null
  fetch.toitdoc = [
    "Fetches the ", toit-gen.ToitdocNameRef p-url, ".\n",
    "Uses the given ", toit-gen.ToitdocNameRef p-timeout, " and\n",
    "  invokes ", toit-gen.ToitdocNameRef p-callback, " on completion.",
  ]
  cls.members.add fetch
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-member-params.toit"]

  expected := """
    class Client:
      /**
      Fetches the \$url.
      Uses the given \$timeout and
        invokes \$callback on completion.
      */
      fetch url --timeout callback:"""
  expect-equals expected code.trim

test-toitdoc-exact-named-block:
  // Test exact ref rendering with named and block params in the signature.
  lib := toit-gen.Library "test-toitdoc-exact-named-block.toit"
  cls := toit-gen.Class "Server" --kind=toit-gen.Class.CLASS

  p1 := toit-gen.VarDefinition.parameter "path"
  p1.name = "path"
  p2 := toit-gen.VarDefinition.parameter "method" --is-named=true
  p2.name = "method"
  p3 := toit-gen.VarDefinition.parameter "handler" --is-block=true
  p3.name = "handler"

  route := toit-gen.Function "route" --parameters=[p1, p2, p3] --return-type=null
  cls.members.add route

  // A top-level function that references the exact overload with all param types.
  helper := toit-gen.Function "setup" --parameters=[] --return-type=null
  helper.toitdoc = [
    "Sets up a route using ", toit-gen.ToitdocExactRef route --holder=cls, ".",
  ]
  lib.functions.add helper
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-exact-named-block.toit"]

  expected := """
    class Server:
      route path --method handler:


    /** Sets up a route using \$(Server.route path --method [handler]). */
    setup:"""
  expect-equals expected code.trim

test-toitdoc-member-no-shadow-global:
  // A class member and a top-level function share the same preferred name.
  // The namer must rename the member to avoid shadowing the global.
  // A toitdoc inside the class referencing the top-level function should
  // use the global's name (which the member can't shadow).
  lib := toit-gen.Library "test-toitdoc-member-no-shadow.toit"

  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS
  member := toit-gen.Function "connect" --parameters=[] --return-type=null
  cls.members.add member

  global-fun := toit-gen.Function "connect" --parameters=[] --return-type=null
  lib.functions.add global-fun

  // Member 'bar' has a toitdoc referencing the top-level 'connect'.
  bar := toit-gen.Function "bar" --parameters=[] --return-type=null
  bar.toitdoc = [
    "See ", toit-gen.ToitdocNameRef global-fun, ".",
  ]
  cls.members.add bar
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-member-no-shadow.toit"]

  // The namer assigns 'connect' to the global function first.
  // The member gets a different name (e.g. 'connect-1').
  // The toitdoc should emit '$connect' since the global got 'connect'
  // and there's no member named 'connect' in this class to shadow it.
  expected := """
    class MyClass:
      connect-1:

      /** See \$connect. */
      bar:


    connect:"""
  expect-equals expected code.trim

test-toitdoc-ref-global-from-class:
  // A class member references a top-level function from its toitdoc.
  // No name collision — just verifying the global ref is emitted
  // unqualified (no holder).
  lib := toit-gen.Library "test-toitdoc-ref-global.toit"

  global-fun := toit-gen.Function "helper" --parameters=[] --return-type=null
  lib.functions.add global-fun

  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS
  member := toit-gen.Function "do-work" --parameters=[] --return-type=null
  member.toitdoc = [
    "Delegates to ", toit-gen.ToitdocNameRef global-fun, ".",
  ]
  cls.members.add member
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-ref-global.toit"]

  expected := """
    class MyClass:
      /** Delegates to \$helper. */
      do-work:


    helper:"""
  expect-equals expected code.trim

test-toitdoc-param-shadows-global:
  // A top-level function has a parameter with the same preferred name
  // as another top-level function.  The namer assigns the function name
  // first (Phase 3), then the parameter (Phase 4/5), so the parameter
  // gets renamed.  The toitdoc references the *function*, which keeps
  // its original name.
  lib := toit-gen.Library "test-toitdoc-param-shadow-global.toit"

  target-fun := toit-gen.Function "process" --parameters=[] --return-type=null
  lib.functions.add target-fun

  p := toit-gen.VarDefinition.parameter "process"
  caller := toit-gen.Function "run" --parameters=[p] --return-type=null
  caller.toitdoc = [
    "Calls ", toit-gen.ToitdocNameRef target-fun, " after setting up ", toit-gen.ToitdocNameRef p, ".",
  ]
  lib.functions.add caller

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-param-shadow-global.toit"]

  // 'process' is assigned to the function.  The parameter gets renamed
  // (e.g. 'process-1') because the global namer already has 'process'.
  // The toitdoc '$process' correctly refers to the function.
  expected := """
    process:

    /** Calls \$process after setting up \$process-1. */
    run process-1:"""
  expect-equals expected code.trim

test-toitdoc-param-shadows-member:
  // A member function has a parameter with the same preferred name
  // as a sibling member.  The namer assigns member names first
  // (Phase 3), then parameters (Phase 4/5), so the parameter gets
  // renamed.  A toitdoc on the function references the sibling member.
  lib := toit-gen.Library "test-toitdoc-param-shadow-member.toit"
  cls := toit-gen.Class "Worker" --kind=toit-gen.Class.CLASS

  // Sibling member 'status'.
  status := toit-gen.Function "status" --parameters=[] --return-type=null
  cls.members.add status

  // Method 'update' with parameter preferred-name 'status'.
  p := toit-gen.VarDefinition.parameter "status"
  update := toit-gen.Function "update" --parameters=[p] --return-type=null
  update.toitdoc = [
    "Updates the ", toit-gen.ToitdocNameRef status, " to ", toit-gen.ToitdocNameRef p, ".",
  ]
  cls.members.add update
  lib.classes.add cls

  program := toit-gen.Program
  program.libraries.add lib

  generated := program.gen --in-memory
  code := generated["test-toitdoc-param-shadow-member.toit"]

  // 'status' is assigned to the member (Phase 3).
  // The parameter gets renamed (e.g. 'status-1') because the member
  // namer already has 'status'.
  // The toitdoc '$status' correctly refers to the sibling member.
  expected := """
    class Worker:
      status:

      /** Updates the \$status to \$status-1. */
      update status-1:"""
  expect-equals expected code.trim
