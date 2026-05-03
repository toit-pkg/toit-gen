// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

COMMON-ABBREVIATIONS_ := {
  "XML",
  "HTTP",
  "HTML",
  "JSON",
  "API",
}

RESERVED_ ::= {
  "constructor",
  "if",
  "it",
  "for",
  "while",
  "class",
  "static",
  "extends",
  "implements",
  "mixin",
  "switch",
  "catch",
  "try",
  "not",
  "and",
  "or",
  "return",
  "none",
  "any",
  "true",
  "false",
  "_",
}

/**
Creates a unique string from $name in the given scope.
*/
unique name/string [--is-free]:
  if is-free.call name: return name
  i := 1
  is-private := name.ends-with "_"
  prefix := is-private ? name[.. name.size - 1] : name
  suffix := is-private ? "_" : ""
  while true:
    attempt := "$prefix-$i$suffix"
    if is-free.call attempt: return attempt
    i++

/** Converts a name to a valid Toit class name (CamelCase). */
toit-class-name name/string --private/bool=false -> string:
  result := to-caml-case (toit-identifier name --private=private)
  first-char := result[..1]
  upper := first-char.to-ascii-upper
  if first-char != upper: result = upper + result[1..]
  return result

/** Converts a name to a valid Toit global name (kebab-case). */
toit-global-name name/string --private/bool=false -> string:
  return toit-kebab-name_ name --private=private

/** Converts a name to a valid Toit prefix name (kebab-case). */
toit-prefix-name name/string --private/bool=false -> string:
  return toit-kebab-name_ name --private=private

/** Converts a name to a valid Toit member name (kebab-case). */
toit-member-name name/string --private/bool=false -> string:
  return toit-kebab-name_ name --private=private

/** Converts a name to a valid Toit local variable name (kebab-case). */
toit-local-name name/string --private/bool=false -> string:
  return toit-kebab-name_ name --private=private

/** Converts a name to a valid Toit constant name (ALL_CAPS). */
toit-constant-name name/string --private/bool=false -> string:
  result := to-caml-case (toit-identifier name --private=private)
  result = result.to-ascii-upper
  return result

toit-kebab-name_ name/string --private/bool=false -> string:
  result := to-kebab-case (toit-identifier name --private=private)
  first-char := result[..1]
  lower := first-char.to-ascii-lower
  if first-char != lower: result = lower + result[1..]
  return result

/**
Converts a string to a valid Toit identifier.
*/
toit-identifier str/string --private/bool=false -> string:
  chars := []
  str.do --runes: | rune/int |
    if 0 <= rune <= 9:
      chars.add rune
    else if 'a' <= rune <= 'z':
      chars.add rune
    else if 'A' <= rune <= 'Z':
      chars.add rune
    else if rune == '-' or rune == '_':
      chars.add rune
    else:
      chars.add rune
  // Make sure we don't have a leading or trailing '-' or two
  // consecutive '-'s.
  to := 0
  last-was-dash := true
  for i := 0; i < chars.size; i++:
    c := chars[i]
    if c == '-':
      if last-was-dash or i == chars.size - 1:
        continue // Skip this character.
      last-was-dash = true
    else:
      last-was-dash = false
    chars[to++] = c
  chars.resize to
  if private: chars.add '_'
  return string.from-runes chars

to-kebab-case id/string -> string:
  chunks := split-into-chunks_ id
  chunks.map --in-place: | str/string |
    str.to-ascii-lower
  return chunks.join "-"

to-caml-case id/string -> string:
  chunks := split-into-chunks_ id
  chunks.map --in-place: | str/string |
    lower := str.to-ascii-lower
    lower[..1].to-ascii-upper + lower[1..]
  return chunks.join ""

split-into-chunks_ str/string -> List:
  result := []
  start := 0
  last-was-upper := false
  for i := 0; i < str.size; i++:
    c := str[i]
    if not c:
      if start == i: start++
      continue  // Unicode.
    is-upper/bool := ?
    if 'A' <= c <= 'Z':
      is-upper = true
      if not last-was-upper and i != start:
        // Caml-case cut-point.
        result.add str[start .. i]
        start = i
      else if last-was-upper and COMMON-ABBREVIATIONS_.contains str[start .. i]:
        // Cut here, even though it's not finished yet.
        // This happens when we have something like 'HTTPRequest'.
        // Might need to be tweaked a bit more...
        result.add str[start .. i]
        start = i
    else if (c == '_' and i != str.size - 1)or c == '-' or c == ' ':
      is-upper = false
      if start != i: result.add str[start .. i]
      start = i + 1
    else:
      // We treat all other characters as if they were normal
      // lower-case. Might need tuning.
      is-upper = false
    last-was-upper = is-upper
  if start != str.size: result.add str[start..]
  return result

/**
Normalizes $name by converting underscores to dashes.

Preserves the trailing underscore for private names.
*/
normalize_ name/string -> string:
  is-private := name.ends-with "_"
  core := is-private ? name[.. name.size - 1] : name
  normalized := core.replace --all "_" "-"
  return is-private ? "$(normalized)_" : normalized

/**
Base class for assigning and reserving names.
*/
abstract class Namer:
  used-names/Set ::= {}
  outer-namer/Namer?

  constructor --outer/Namer?=null:
    outer-namer = outer

  /**
  Reserves a specific $name.
  */
  reserve name/string --check/bool=true --deep/bool=false -> none:
    normalized := normalize_ name
    assert: not check or not used-names.contains normalized
    used-names.add normalized
    if deep and outer-namer:
      outer-namer.reserve normalized --check=false --deep=true

  /**
  Registers a unique variant of the given $name and returns it.
  */
  use-unique name/string -> string:
    unique-name := unique name --is-free=: is-free it
    used-names.add unique-name
    return unique-name

  /** Returns true if $name is available. */
  is-free name/string -> bool:
    normalized := normalize_ name
    namer/Namer? := this
    if RESERVED_.contains normalized: return false
    while namer:
      if namer.used-names.contains normalized: return false
      namer = namer.outer-namer
    return true

/**
A namer for the global scope.
*/
class GlobalNamer extends Namer:

  /** Derives and registers a valid unique class name. */
  use-class preferred/string --private/bool=false -> string:
    return use-unique (toit-class-name preferred --private=private)

  /** Derives and registers a valid unique global variable name. */
  use-global preferred/string --private/bool=false -> string:
    return use-unique (toit-global-name preferred --private=private)

  use-constant preferred/string --private/bool=false -> string:
    return use-unique (toit-constant-name preferred --private=private)

  /** Derives and registers a valid unique import prefix name. */
  use-prefix preferred/string --private/bool=false --also-avoid/Set={} -> string:
    name := toit-prefix-name preferred --private=private
    if also-avoid.is-empty:
      return use-unique name
    unique-name := unique name --is-free=: is-free it and not (also-avoid.contains it)
    used-names.add unique-name
    return unique-name

  /**
  Assigns a name for $preferred, allowing overloads to share names.

  Uses the $cache to track already-assigned names by their computed
    toit name. If the same toit name was already assigned, the cached
    result is returned.
  */
  use-shared-global preferred/string --private/bool=false --cache/Map -> string:
    toit-name := toit-global-name preferred --private=private
    cached := cache.get toit-name
    if cached: return cached
    result := use-unique toit-name
    cache[toit-name] = result
    return result

  new-member-namer -> MemberNamer:
    return MemberNamer this

  new-local-namer -> LocalNamer:
    return LocalNamer this

/**
A namer for a class or interface member scope.
*/
class MemberNamer extends Namer:
  constructor global-namer/GlobalNamer:
    super --outer=global-namer

  /** Derives and registers a valid unique method or field name. */
  use-member preferred/string --private/bool=false -> string:
    return use-unique (toit-member-name preferred --private=private)

  use-constant preferred/string --private/bool=false -> string:
    return use-unique (toit-constant-name preferred --private=private)

  /**
  Assigns a name for $preferred, allowing overloads to share names.

  Uses the $cache to track already-assigned names by their computed
    toit name. If the same toit name was already assigned, the cached
    result is returned.
  */
  use-shared-member preferred/string --private/bool=false --cache/Map -> string:
    toit-name := toit-member-name preferred --private=private
    cached := cache.get toit-name
    if cached: return cached
    result := use-unique toit-name
    cache[toit-name] = result
    return result

  new-local-namer -> LocalNamer:
    return LocalNamer this

/**
A namer for a local scope (e.g. inside a function).
*/
class LocalNamer extends Namer:
  constructor outer/Namer:
    super --outer=outer

  /** Derives and registers a valid unique local variable name. */
  use-local preferred/string -> string:
    return use-unique (toit-local-name preferred)
