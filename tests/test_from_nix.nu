# Tests for `from nix` and roundtrip (`to nix | from nix`) — requires Nix in PATH.
#
# Each test is a function annotated with #[test], following the nushell
# std testing convention.  The runner at the bottom of this file is a
# temporary workaround: nushell 0.113.1 does not ship a working
# `std testing run-tests` command.
#
# Run now:
#   nu tests/test_from_nix.nu
#
# Run once a proper runner is available:
#   nutest run tests/
#   nu -c 'use std testing; testing run-tests --path tests/'

use std assert
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

#[test]
def "test from nix builtins" [] {
  assert equal ("builtins.length [ 1 2 3 ]" | from nix) 3
}

#[test]
def "test from nix let expression" [] {
  assert equal ("let x = 10; in x * x" | from nix) 100
}


# ── from nix: Nix language features ──────────────────────────────────────────

#[test]
def "test from nix with expression" [] {
  let r = ("with { x = 10; y = 20; }; { sum = x + y; product = x * y; }" | from nix)
  assert equal $r.sum 30
  assert equal $r.product 200
}

#[test]
def "test from nix string interpolation" [] {
  # Nix evaluates ${name} interpolation before returning the string.
  assert equal ('let name = "world"; in "Hello, ${name}!"' | from nix) "Hello, world!"
}

#[test]
def "test from nix replaceStrings" [] {
  let r = ('builtins.replaceStrings ["foo" "bar"] ["baz" "qux"] "foo and bar"' | from nix)
  assert equal $r "baz and qux"
}

#[test]
def "test from nix nested let" [] {
  # Inner let can shadow outer bindings.
  assert equal ("let a = 2; b = let c = 3; in a * c; in a + b" | from nix) 8
}

#[test]
def "test from nix builtins mapAttrs" [] {
  assert equal ("builtins.mapAttrs (k: v: v + 1) { a = 1; b = 2; }" | from nix) {a: 2, b: 3}
}

#[test]
def "test from nix builtins filter" [] {
  assert equal ("builtins.filter (x: x > 2) [ 1 2 3 4 5 ]" | from nix) [3 4 5]
}

#[test]
def "test from nix builtins concatLists" [] {
  assert equal ("builtins.concatLists [[1 2] [3 4] [5]]" | from nix) [1 2 3 4 5]
}

#[test]
def "test from nix builtins listToAttrs" [] {
  let r = ('builtins.listToAttrs [{name = "a"; value = 1;} {name = "b"; value = 2;}]' | from nix)
  assert equal $r {a: 1, b: 2}
}

#[test]
def "test from nix lambda and map" [] {
  assert equal ("let f = x: x * x; in builtins.map f [1 2 3 4 5]" | from nix) [1 4 9 16 25]
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
  # null values inside a list must survive the round-trip.
  let r = ([1 null "hello" null 3] | to nix | from nix)
  assert equal ($r | length) 5
  assert equal ($r | get 1) null
  assert equal ($r | get 2) "hello"
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


# ── Real nixpkgs data ─────────────────────────────────────────────────────────
# Fetch live package metadata and verify it survives a full round-trip.

#[test]
def "test nixpkgs hello.meta roundtrip" [] {
  let original = (from nix nixpkgs#hello.meta)
  assert equal ($original | to nix | from nix) $original
}

#[test]
def "test nixpkgs git.meta roundtrip" [] {
  let original = (from nix nixpkgs#git.meta)
  assert equal ($original | to nix | from nix) $original
}

#[test]
def "test nixpkgs nushell.meta roundtrip" [] {
  let original = (from nix nixpkgs#nushell.meta)
  assert equal ($original | to nix | from nix) $original
}

#[test]
def "test nixpkgs curl.meta roundtrip" [] {
  let original = (from nix nixpkgs#curl.meta)
  assert equal ($original | to nix | from nix) $original
}

#[test]
def "test nixpkgs ripgrep.meta roundtrip" [] {
  let original = (from nix nixpkgs#ripgrep.meta)
  assert equal ($original | to nix | from nix) $original
}

#[test]
def "test nixpkgs python3.meta roundtrip" [] {
  let original = (from nix nixpkgs#python3.meta)
  assert equal ($original | to nix | from nix) $original
}


# ── to nix → nix eval: generated Nix is syntactically valid ──────────────────

#[test]
def "test to nix nixos-style config is valid" [] {
  # Build a realistic NixOS-style config in Nu, serialise it, then let Nix
  # evaluate it to confirm the output is syntactically and semantically valid.
  let cfg = {
    networking: {hostName: "nixbox", firewall: {enable: true, allowedTCPPorts: [22 80 443]}}
    services: {openssh: {enable: true}}
    environment: {systemPackages: ["git" "vim" "curl"]}
  }
  let restored = ($cfg | to nix | from nix)
  assert equal $restored.networking.hostName "nixbox"
  assert equal $restored.networking.firewall.allowedTCPPorts [22 80 443]
  assert equal $restored.services.openssh.enable true
  assert equal $restored.environment.systemPackages ["git" "vim" "curl"]
}

#[test]
def "test to nix path-info style is valid" [] {
  # Simulate the shape returned by `nix path-info --json`.
  let info = {
    narHash: "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    narSize: 1234567
    references: ["/nix/store/abc-glibc-2.38" "/nix/store/def-gcc-13.2"]
    valid: true
  }
  let restored = ($info | to nix | from nix)
  assert equal $restored.narSize 1234567
  assert equal ($restored.references | length) 2
  assert equal $restored.valid true
}

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


# ── Runner ────────────────────────────────────────────────────────────────────
# Temporary workaround: nushell 0.113.1 does not ship a working
# `std testing run-tests` command.  This section dispatches every test
# function above and can be deleted once a proper runner is available.
#
# To use a proper runner (when available):
#   nutest run tests/
#   nu -c 'use std testing; testing run-tests --path tests/'

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

let $_results = [
  # from nix: expression evaluation
  (_run "from nix int expr"            { test from nix int expr })
  (_run "from nix bool true"           { test from nix bool true })
  (_run "from nix bool false"          { test from nix bool false })
  (_run "from nix null"                { test from nix null })
  (_run "from nix string"              { test from nix string })
  (_run "from nix list"                { test from nix list })
  (_run "from nix attrset"             { test from nix attrset })
  (_run "from nix nested attrset"      { test from nix nested attrset })
  (_run "from nix builtins"            { test from nix builtins })
  (_run "from nix let expression"      { test from nix let expression })

  # from nix: Nix language features
  (_run "from nix with expression"     { test from nix with expression })
  (_run "from nix string interpolation" { test from nix string interpolation })
  (_run "from nix replaceStrings"      { test from nix replaceStrings })
  (_run "from nix nested let"          { test from nix nested let })
  (_run "from nix builtins mapAttrs"   { test from nix builtins mapAttrs })
  (_run "from nix builtins filter"     { test from nix builtins filter })
  (_run "from nix builtins concatLists" { test from nix builtins concatLists })
  (_run "from nix builtins listToAttrs" { test from nix builtins listToAttrs })
  (_run "from nix lambda and map"      { test from nix lambda and map })

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

  # Real nixpkgs data
  (_run "nixpkgs hello.meta roundtrip"   { test nixpkgs hello.meta roundtrip })
  (_run "nixpkgs git.meta roundtrip"     { test nixpkgs git.meta roundtrip })
  (_run "nixpkgs nushell.meta roundtrip" { test nixpkgs nushell.meta roundtrip })
  (_run "nixpkgs curl.meta roundtrip"    { test nixpkgs curl.meta roundtrip })
  (_run "nixpkgs ripgrep.meta roundtrip" { test nixpkgs ripgrep.meta roundtrip })
  (_run "nixpkgs python3.meta roundtrip" { test nixpkgs python3.meta roundtrip })

  # to nix → nix eval validity
  (_run "to nix nixos-style config is valid"    { test to nix nixos-style config is valid })
  (_run "to nix path-info style is valid"       { test to nix path-info style is valid })
  (_run "to nix all primitive types in one attrset" { test to nix all primitive types in one attrset })

  # from nix --file
  (_run "from nix --file"              { test from nix --file })
]

let $_n_pass = ($_results | where { $in } | length)
let $_n_fail  = ($_results | where { not $in } | length)
print $"\n($_n_pass) passed, ($_n_fail) failed"
if $_n_fail > 0 { exit 1 }
