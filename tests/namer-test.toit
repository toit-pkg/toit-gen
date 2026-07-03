// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *

import toit-gen

main:
  test-bootstrap
  test-fixed-name-propagation
  test-unnamed-params
  test-prefixes-and-locals
  test-locals-and-blocks
  test-global-clashes
  test-cross-class-same-member
  test-cross-class-same-field
  test-cross-class-same-named-param
  test-prefix-vs-deep-member
  test-prefix-vs-field
  test-global-function-and-class-member
  test-field-and-method-same-name
  test-static-function-naming
  test-private-naming
  test-named-param-does-not-shadow-global
  test-overloaded-global-functions
  test-overloaded-members-renamed-together
  test-overloaded-members-with-field
  // Dash/underscore equivalence tests.
  test-fixed-underscore-blocks-dash
  test-underscore-dash-global-functions
  test-underscore-dash-member-overloads
  test-underscore-dash-local-clash
  test-underscore-dash-prefix-vs-member

test-bootstrap:
  cls := toit-gen.Class "MyClass"
      --kind=toit-gen.Class.CLASS
  fun := toit-gen.Function "myMethod" --parameters=[] --return-type=null
  cls.members.add fun
  library := toit-gen.Library "my_library.toit"
  library.classes.add cls
  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory  // Triggers assign-names_.
  expect-equals "MyClass" cls.name
  expect-equals "my-method" fun.name

test-fixed-name-propagation:
  // A class with a method that has a fixed parameter 'foo'
  // should block a field in that class from being named 'foo'.
  cls := toit-gen.Class "MyClass"
      --kind=toit-gen.Class.CLASS

  fixed-param := toit-gen.VarDefinition.parameter "foo"
  fixed-param.name = "foo" // Forced name.

  fun := toit-gen.Function "myMethod" --parameters=[fixed-param] --return-type=null
  cls.members.add fun

  field := toit-gen.VarDefinition.field "foo" --initial=null
  cls.fields.add field

  library := toit-gen.Library "my_library.toit"
  library.classes.add cls
  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory

  expect-equals "foo" fixed-param.name
  // The field should be renamed from 'foo' because 'foo' is a fixed param inside the class.
  expect-not-equals "foo" field.name

test-unnamed-params:
  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS

  // Named param gets the name "foo".
  named-param := toit-gen.VarDefinition.parameter "foo" --is-named=true

  // Unnamed param also prefers "foo".
  unnamed-param := toit-gen.VarDefinition.parameter "foo" --is-named=false

  fun := toit-gen.Function "myMethod" --parameters=[named-param, unnamed-param] --return-type=null
  cls.members.add fun

  library := toit-gen.Library "my_library.toit"
  library.classes.add cls
  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory

  expect-equals "foo" named-param.name
  // Unnamed param should yield to the named param and become foo-1.
  expect-not-equals "foo" unnamed-param.name

test-prefixes-and-locals:
  // Library with an import prefix 'my_prefix' and a class with a member 'my_prefix'.
  // The prefix should yield to the member and become 'my-prefix-1'.
  library := toit-gen.Library "my_library.toit"

  imp := toit-gen.Import ["some", "pkg"] --preferred-prefix="my_prefix"
  library.imports.add imp

  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS
  fun := toit-gen.Function "my_prefix" --parameters=[] --return-type=null
  cls.members.add fun
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory

  expect-equals "my-prefix" fun.name
  // Prefix should not clash with the member name, so it should get a suffix.
  expect-not-equals "my-prefix" imp.prefix

test-locals-and-blocks:
  // A local variable and a block parameter should not clash if they are in the same scope,
  // or rather, block parameters get unique IDs from the enclosing local namer.
  cls := toit-gen.Class "MyClass" --kind=toit-gen.Class.CLASS

  // A local named 'foo'.
  local1 := toit-gen.VarDefinition.local "foo" --initial=(toit-gen.Literal 1)
  local2 := toit-gen.VarDefinition.local "foo" --initial=(toit-gen.Literal 2)

  seq := toit-gen.Sequence
  seq.add (toit-gen.LocalDefinition local1)
  seq.add (toit-gen.LocalDefinition local2)

  fun := toit-gen.Function "myMethod" --parameters=[] --return-type=null
  fun.body = seq
  cls.members.add fun

  library := toit-gen.Library "my_library.toit"
  library.classes.add cls
  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory

  expect-equals "foo" local1.name
  expect-not-equals "foo" local2.name

test-global-clashes:
  // Two classes with the same preferred name.
  cls1 := toit-gen.Class "Foo" --kind=toit-gen.Class.CLASS
  cls2 := toit-gen.Class "Foo" --kind=toit-gen.Class.CLASS

  library := toit-gen.Library "my_library.toit"
  library.classes.add cls1
  library.classes.add cls2

  program := toit-gen.Program
  program.libraries.add library

  program.gen --in-memory

  expect-equals "Foo" cls1.name
  // Second class gets a suffix.
  expect-not-equals "Foo" cls2.name

// ---------------------------------------------------------------------------
// New tests below.
// ---------------------------------------------------------------------------

test-cross-class-same-member:
  // Two classes each with a member named 'foo'.
  // Both should keep their preferred name since member namers are independent.
  cls-a := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  fun-a := toit-gen.Function "foo" --parameters=[] --return-type=null
  cls-a.members.add fun-a

  cls-b := toit-gen.Class "B" --kind=toit-gen.Class.CLASS
  fun-b := toit-gen.Function "foo" --parameters=[] --return-type=null
  cls-b.members.add fun-b

  library := toit-gen.Library "lib.toit"
  library.classes.add cls-a
  library.classes.add cls-b

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "foo" fun-a.name
  expect-equals "foo" fun-b.name

test-cross-class-same-field:
  // Two classes each with a field named 'bar'.
  // Both should keep their preferred name.
  cls-a := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  field-a := toit-gen.VarDefinition.field "bar" --initial=null
  cls-a.fields.add field-a

  cls-b := toit-gen.Class "B" --kind=toit-gen.Class.CLASS
  field-b := toit-gen.VarDefinition.field "bar" --initial=null
  cls-b.fields.add field-b

  library := toit-gen.Library "lib.toit"
  library.classes.add cls-a
  library.classes.add cls-b

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "bar" field-a.name
  expect-equals "bar" field-b.name

test-cross-class-same-named-param:
  // Two classes each with a method 'foo --bar:'.
  // The named param 'bar' should be the same in both classes.
  cls-a := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  param-a := toit-gen.VarDefinition.parameter "bar" --is-named=true
  fun-a := toit-gen.Function "foo" --parameters=[param-a] --return-type=null
  cls-a.members.add fun-a

  cls-b := toit-gen.Class "B" --kind=toit-gen.Class.CLASS
  param-b := toit-gen.VarDefinition.parameter "bar" --is-named=true
  fun-b := toit-gen.Function "foo" --parameters=[param-b] --return-type=null
  cls-b.members.add fun-b

  library := toit-gen.Library "lib.toit"
  library.classes.add cls-a
  library.classes.add cls-b

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "foo" fun-a.name
  expect-equals "foo" fun-b.name
  expect-equals "bar" param-a.name
  expect-equals "bar" param-b.name

test-prefix-vs-deep-member:
  // Import with preferred prefix 'foo' and a class with member 'foo'.
  // The prefix should yield because 'foo' is used as a member name.
  library := toit-gen.Library "lib.toit"

  imp := toit-gen.Import ["some", "pkg"] --preferred-prefix="foo"
  library.imports.add imp

  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  fun := toit-gen.Function "foo" --parameters=[] --return-type=null
  cls.members.add fun
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "foo" fun.name
  // Prefix should be renamed to avoid clashing with the member.
  expect-not-equals "foo" imp.prefix

test-prefix-vs-field:
  // Import with preferred prefix 'bar' and a class with field 'bar'.
  // The prefix should yield because 'bar' is used as a field name.
  library := toit-gen.Library "lib.toit"

  imp := toit-gen.Import ["some", "pkg"] --preferred-prefix="bar"
  library.imports.add imp

  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  field := toit-gen.VarDefinition.field "bar" --initial=null
  cls.fields.add field
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "bar" field.name
  // Prefix should be renamed to avoid clashing with the field.
  expect-not-equals "bar" imp.prefix

test-global-function-and-class-member:
  // A global function and a class member with the same preferred name.
  // The global function plays at global scope; the member is in class scope.
  // They should not interfere with each other.
  library := toit-gen.Library "lib.toit"

  global-fun := toit-gen.Function "do_thing" --parameters=[] --return-type=null
  library.functions.add global-fun

  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  member-fun := toit-gen.Function "do_thing" --parameters=[] --return-type=null
  cls.members.add member-fun
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  // Both should keep "do-thing" since they are in different scopes.
  // However, member namer checks global namer, so the member might get renamed.
  // The global function is assigned first (phase 3), so it gets "do-thing".
  expect-equals "do-thing" global-fun.name
  // The member namer's parent is the global namer, so "do-thing" is taken.
  expect-not-equals "do-thing" member-fun.name

test-field-and-method-same-name:
  // A class with both a field and method named 'value'.
  // They share the same member namer; overloads keep the same name.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  field := toit-gen.VarDefinition.field "value" --initial=null
  cls.fields.add field

  fun := toit-gen.Function "value" --parameters=[] --return-type=null
  cls.members.add fun

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  // Both field and method share the name 'value'.
  expect-equals "value" fun.name
  expect-equals "value" field.name

test-static-function-naming:
  // Static functions and instance members share the member namer.
  // With overloaded preferred names, they share the assigned name too.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  static-fun := toit-gen.Function "helper" --parameters=[] --return-type=null
  cls.static-functions.add static-fun

  instance-fun := toit-gen.Function "helper" --parameters=[] --return-type=null
  cls.members.add instance-fun

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  // Both share the same name since they're overloads at the member level.
  expect-equals "helper" instance-fun.name
  expect-equals "helper" static-fun.name

test-private-naming:
  // Explicit is-private should yield a name suffixed with '_'.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  priv-fun := toit-gen.Function "secret" --parameters=[] --return-type=null --is-private=true
  cls.members.add priv-fun

  pub-fun := toit-gen.Function "open" --parameters=[] --return-type=null
  cls.members.add pub-fun

  priv-field := toit-gen.VarDefinition.field "stash" --is-private=true --initial=null
  cls.fields.add priv-field

  priv-cls := toit-gen.Class "Hidden" --kind=toit-gen.Class.CLASS --is-private=true

  library := toit-gen.Library "lib.toit"
  library.classes.add cls
  library.classes.add priv-cls

  priv-global-fun := toit-gen.Function "global-secret" --parameters=[] --return-type=null --is-private=true
  library.functions.add priv-global-fun

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "secret_" priv-fun.name
  expect-equals "open" pub-fun.name
  expect-equals "stash_" priv-field.name
  expect-equals "Hidden_" priv-cls.name
  expect-equals "global-secret_" priv-global-fun.name

test-named-param-does-not-shadow-global:
  // A named parameter in a global function should not clash with the class name.
  library := toit-gen.Library "lib.toit"

  cls := toit-gen.Class "Foo" --kind=toit-gen.Class.CLASS
  library.classes.add cls

  param := toit-gen.VarDefinition.parameter "foo" --is-named=true
  fun := toit-gen.Function "do_thing" --parameters=[param] --return-type=null
  library.functions.add fun

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "Foo" cls.name
  expect-equals "do-thing" fun.name
  // 'foo' as a named param shouldn't clash with class 'Foo' (different case).
  expect-equals "foo" param.name

test-overloaded-global-functions:
  // Two global functions with the same preferred name.
  // Both should keep "foo" since overloads share the name.
  library := toit-gen.Library "lib.toit"

  fun1 := toit-gen.Function "foo" --parameters=[] --return-type=null
  library.functions.add fun1

  param := toit-gen.VarDefinition.parameter "x"
  fun2 := toit-gen.Function "foo" --parameters=[param] --return-type=null
  library.functions.add fun2

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "foo" fun1.name
  expect-equals "foo" fun2.name

test-overloaded-members-renamed-together:
  // A global function 'foo' clashes with member overloads 'foo x:' and 'foo x y:'.
  // Both members should be renamed to the *same* name.
  library := toit-gen.Library "lib.toit"

  global-fun := toit-gen.Function "foo" --parameters=[] --return-type=null
  library.functions.add global-fun

  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  param1 := toit-gen.VarDefinition.parameter "x"
  member1 := toit-gen.Function "foo" --parameters=[param1] --return-type=null
  cls.members.add member1

  param2a := toit-gen.VarDefinition.parameter "x"
  param2b := toit-gen.VarDefinition.parameter "y"
  member2 := toit-gen.Function "foo" --parameters=[param2a, param2b] --return-type=null
  cls.members.add member2

  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  // Global keeps "foo".
  expect-equals "foo" global-fun.name
  // Both members are renamed, but share the same renamed name.
  expect-not-equals "foo" member1.name
  expect-equals member1.name member2.name

test-overloaded-members-with-field:
  // A class with a field 'bar' and two overloaded methods 'bar'.
  // All three should share the name.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  field := toit-gen.VarDefinition.field "bar" --initial=null
  cls.fields.add field

  fun1 := toit-gen.Function "bar" --parameters=[] --return-type=null
  cls.members.add fun1

  param := toit-gen.VarDefinition.parameter "x"
  fun2 := toit-gen.Function "bar" --parameters=[param] --return-type=null
  cls.members.add fun2

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "bar" field.name
  expect-equals "bar" fun1.name
  expect-equals "bar" fun2.name

// ---------------------------------------------------------------------------
// Dash/underscore equivalence tests.
// In Toit, 'foo-bar' and 'foo_bar' are the same identifier.
// ---------------------------------------------------------------------------

test-fixed-underscore-blocks-dash:
  // A fixed parameter named 'foo_bar' should block a field from getting
  // 'foo-bar' (the equivalent identifier).
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  fixed-param := toit-gen.VarDefinition.parameter "foo_bar"
  fixed-param.name = "foo_bar"  // Pre-assigned with underscore form.

  fun := toit-gen.Function "my-method" --parameters=[fixed-param] --return-type=null
  cls.members.add fun

  field := toit-gen.VarDefinition.field "foo_bar" --initial=null
  cls.fields.add field

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "foo_bar" fixed-param.name
  // The field would normally get 'foo-bar', but that clashes with the
  // fixed 'foo_bar' (same Toit identifier). So it must be renamed.
  expect-not-equals "foo-bar" field.name
  expect-not-equals "foo_bar" field.name

test-underscore-dash-global-functions:
  // Two global function overloads: one with preferred name 'foo_bar', the
  // other with 'foo-bar'. Both normalize to 'foo-bar' and should share
  // the same name via the overload cache.
  library := toit-gen.Library "lib.toit"

  fun1 := toit-gen.Function "foo_bar" --parameters=[] --return-type=null
  library.functions.add fun1

  param := toit-gen.VarDefinition.parameter "x"
  fun2 := toit-gen.Function "foo-bar" --parameters=[param] --return-type=null
  library.functions.add fun2

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  // Both should normalize to "foo-bar".
  expect-equals "foo-bar" fun1.name
  expect-equals "foo-bar" fun2.name

test-underscore-dash-member-overloads:
  // Two member overloads in the same class: one preferred 'do_thing', the
  // other preferred 'do-thing'. They should get the same assigned name.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  fun1 := toit-gen.Function "do_thing" --parameters=[] --return-type=null
  cls.members.add fun1

  param := toit-gen.VarDefinition.parameter "x"
  fun2 := toit-gen.Function "do-thing" --parameters=[param] --return-type=null
  cls.members.add fun2

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "do-thing" fun1.name
  expect-equals "do-thing" fun2.name

test-underscore-dash-local-clash:
  // Two locals: one preferred 'my_var', the other 'my-var'.
  // They normalize to the same name, so the second must be renamed.
  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS

  local1 := toit-gen.VarDefinition.local "my_var" --initial=(toit-gen.Literal 1)
  local2 := toit-gen.VarDefinition.local "my-var" --initial=(toit-gen.Literal 2)

  seq := toit-gen.Sequence
  seq.add (toit-gen.LocalDefinition local1)
  seq.add (toit-gen.LocalDefinition local2)

  fun := toit-gen.Function "my-method" --parameters=[] --return-type=null
  fun.body = seq
  cls.members.add fun

  library := toit-gen.Library "lib.toit"
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "my-var" local1.name
  // Second local has the same normalized name, so it gets a suffix.
  expect-not-equals "my-var" local2.name

test-underscore-dash-prefix-vs-member:
  // Import with preferred prefix 'my_util' and a class method 'my-util'.
  // They are the same Toit identifier, so the prefix must yield.
  library := toit-gen.Library "lib.toit"

  imp := toit-gen.Import ["some", "pkg"] --preferred-prefix="my_util"
  library.imports.add imp

  cls := toit-gen.Class "A" --kind=toit-gen.Class.CLASS
  fun := toit-gen.Function "my-util" --parameters=[] --return-type=null
  cls.members.add fun
  library.classes.add cls

  program := toit-gen.Program
  program.libraries.add library
  program.gen --in-memory

  expect-equals "my-util" fun.name
  // Prefix 'my_util' normalizes to 'my-util', same as the member.
  // So it must be renamed.
  expect-not-equals "my-util" imp.prefix
  expect-not-equals "my_util" imp.prefix
