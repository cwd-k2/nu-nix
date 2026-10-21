# Tests for `from nix` and roundtrip (`to nix | from nix`) — requires Nix in PATH.
#
# Each test is a function annotated with #[test], following the Nushell
# testing convention. The self-contained runner at the bottom keeps the flake
# check independent of third-party test runners.
#
# Run now:
#   nu tests/test_from_nix.nu
#
# The annotations also allow external runners:
#   nutest run tests/

use ./support/assert.nu
use ../package/scripts/nu-nix/mod.nu *


# ── from nix: expression evaluation ──────────────────────────────────────────

#[test]
def "test from nix int expr" [] {
  assert equal ("1 + 1" | from nix) 2
}

#[test]
def "test from nix bool true" [] {
  assert equal ("true" | from nix) true
}

#[test]
def "test from nix bool false" [] {
  assert equal ("false" | from nix) false
}

#[test]
def "test from nix null" [] {
  assert equal ("null" | from nix) null
}

#[test]
def "test from nix string" [] {
  assert equal ('"hello"' | from nix) "hello"
}

#[test]
def "test from nix list" [] {
  assert equal ("[ 1 2 3 ]" | from nix) [1 2 3]
}

#[test]
def "test from nix attrset" [] {
  assert equal ("{ x = 1; y = true; }" | from nix) {x: 1, y: true}
}

#[test]
def "test from nix nested attrset" [] {
  assert equal (("{ a = { b = 42; }; }" | from nix).a.b) 42
}

# ── Roundtrip: to nix | from nix recovers the original value ─────────────────

#[test]
def "test roundtrip null" [] {
  assert equal (null | to nix | from nix) null
}

#[test]
def "test roundtrip bool true" [] {
  assert equal (true | to nix | from nix) true
}

#[test]
def "test roundtrip bool false" [] {
  assert equal (false | to nix | from nix) false
}

#[test]
def "test roundtrip int" [] {
  assert equal (42 | to nix | from nix) 42
}

#[test]
def "test roundtrip negative int" [] {
  assert equal (-5 | to nix | from nix) (-5)
}

#[test]
def "test roundtrip string" [] {
  assert equal ("hello" | to nix | from nix) "hello"
}

#[test]
def "test roundtrip string with quotes" [] {
  let s = 'say "hi"'
  assert equal ($s | to nix | from nix) $s
}

#[test]
def "test roundtrip string with newline" [] {
  let s = $"a(char newline)b"
  assert equal ($s | to nix | from nix) $s
}

#[test]
def "test roundtrip string with backslash" [] {
  let s = 'a\b'
  assert equal ($s | to nix | from nix) $s
}

#[test]
def "test roundtrip antiquote" [] {
  let s = '${HOME}'
  assert equal ($s | to nix | from nix) $s
}

#[test]
def "test roundtrip empty list" [] {
  assert equal ([] | to nix | from nix) []
}

#[test]
def "test roundtrip int list" [] {
  assert equal ([1 2 3] | to nix | from nix) [1 2 3]
}

#[test]
def "test roundtrip string list" [] {
  assert equal (["a" "b" "c"] | to nix | from nix) ["a" "b" "c"]
}

#[test]
def "test roundtrip list with nulls" [] {
  assert equal ([1 null "hello" null 3] | to nix | from nix) [1 null "hello" null 3]
}

#[test]
def "test roundtrip simple record" [] {
  let r = {name: "hello", broken: false, priority: 5}
  assert equal ($r | to nix | from nix) $r
}

#[test]
def "test roundtrip nested record" [] {
  let r = {a: {b: {c: 42}}}
  assert equal ($r | to nix | from nix) $r
}

#[test]
def "test roundtrip record with list" [] {
  let r = {tags: ["x" "y"], count: 2}
  assert equal ($r | to nix | from nix) $r
}

#[test]
def "test roundtrip float 1.0 stays float" [] {
  # The float type must be preserved; 1.0 must not collapse to the int 1.
  let result = (1.0 | to nix | from nix)
  assert equal ($result | describe) "float"
  assert equal $result 1.0
}

#[test]
def "test roundtrip float 3.14" [] {
  assert equal (3.14 | to nix | from nix) 3.14
}

#[test]
def "test roundtrip large int" [] {
  assert equal (9007199254740992 | to nix | from nix) 9007199254740992
}

#[test]
def "test roundtrip negative float" [] {
  assert equal (-3.14 | to nix | from nix) (-3.14)
}


# ── to nix → nix eval: generated Nix is syntactically valid ──────────────────

#[test]
def "test to nix all primitive types in one attrset" [] {
  # Every primitive type must survive a to nix → from nix round-trip.
  let mixed = {
    a-bool: true, an-int: 42, a-float: 3.14,
    a-string: "hello", a-null: null,
    a-list: [1 2 3], nested: {x: 1}
  }
  let restored = ($mixed | to nix | from nix)
  assert equal $restored.a-bool   true
  assert equal $restored.an-int   42
  assert equal $restored.a-float  3.14
  assert equal $restored.a-string "hello"
  assert equal $restored.a-null   null
  assert equal $restored.a-list   [1 2 3]
  assert equal $restored.nested   {x: 1}
}


# ── from nix --file ───────────────────────────────────────────────────────────

#[test]
def "test from nix --file" [] {
  let f = $"/tmp/nu-nix-test-(random uuid | str replace --all '-' '').nix"
  '{ answer = 42; greeting = "hello"; }' | save $f
  let result = (from nix --file $f)
  rm $f
  assert equal $result.answer 42
  assert equal $result.greeting "hello"
}

#[test]
def "test from nix rejects missing input" [] {
  assert error { from nix }
}

#[test]
def "test from nix rejects ambiguous source" [] {
  assert error { from nix nixpkgs#hello --file ./flake.nix }
  assert error { "1 + 1" | from nix nixpkgs#hello }
  assert error { "1 + 1" | from nix --file ./flake.nix }
}


# ── Runner ────────────────────────────────────────────────────────────────────
# Self-contained dispatch for hermetic flake checks.

def _run [name: string, f: closure]: nothing -> bool {
  try {
    do $f
    print $"(ansi green)PASS(ansi reset) ($name)"
    true
  } catch {|e|
    print $"(ansi red)FAIL(ansi reset) ($name)"
    print $"     ($e.msg)"
    false
  }
}

let _core_results = [
  # from nix: expression evaluation
  (_run "from nix int expr"            { test from nix int expr })
  (_run "from nix bool true"           { test from nix bool true })
  (_run "from nix bool false"          { test from nix bool false })
  (_run "from nix null"                { test from nix null })
  (_run "from nix string"              { test from nix string })
  (_run "from nix list"                { test from nix list })
  (_run "from nix attrset"             { test from nix attrset })
  (_run "from nix nested attrset"      { test from nix nested attrset })
  # Roundtrip
  (_run "roundtrip null"               { test roundtrip null })
  (_run "roundtrip bool true"          { test roundtrip bool true })
  (_run "roundtrip bool false"         { test roundtrip bool false })
  (_run "roundtrip int"                { test roundtrip int })
  (_run "roundtrip negative int"       { test roundtrip negative int })
  (_run "roundtrip string"             { test roundtrip string })
  (_run "roundtrip string with quotes" { test roundtrip string with quotes })
  (_run "roundtrip string with newline" { test roundtrip string with newline })
  (_run "roundtrip string with backslash" { test roundtrip string with backslash })
  (_run "roundtrip antiquote"          { test roundtrip antiquote })
  (_run "roundtrip empty list"         { test roundtrip empty list })
  (_run "roundtrip int list"           { test roundtrip int list })
  (_run "roundtrip string list"        { test roundtrip string list })
  (_run "roundtrip list with nulls"    { test roundtrip list with nulls })
  (_run "roundtrip simple record"      { test roundtrip simple record })
  (_run "roundtrip nested record"      { test roundtrip nested record })
  (_run "roundtrip record with list"   { test roundtrip record with list })
  (_run "roundtrip float 1.0 stays float" { test roundtrip float 1.0 stays float })
  (_run "roundtrip float 3.14"         { test roundtrip float 3.14 })
  (_run "roundtrip large int"          { test roundtrip large int })
  (_run "roundtrip negative float"     { test roundtrip negative float })

  # to nix → nix eval validity
  (_run "to nix all primitive types in one attrset" { test to nix all primitive types in one attrset })

  # from nix --file
  (_run "from nix --file"              { test from nix --file })
  (_run "from nix rejects missing input" { test from nix rejects missing input })
  (_run "from nix rejects ambiguous source" { test from nix rejects ambiguous source })
]

let _results = $_core_results

let _n_pass = ($_results | where { $in } | length)
let _n_fail  = ($_results | where { not $in } | length)
print $"\n($_n_pass) passed, ($_n_fail) failed"
if $_n_fail > 0 { exit 1 }
