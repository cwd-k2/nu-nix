# Tests for `to nix` — pure Nushell, no Nix evaluation required.
#
# Each test is a function annotated with #[test], following the nushell
# std testing convention.  The runner at the bottom of this file is a
# temporary workaround: nushell 0.113.1 does not ship a working
# `std testing run-tests` command.
#
# Run now:
#   nu tests/test_to_nix.nu
#
# Run once a proper runner is available:
#   nutest run tests/
#   nu -c 'use std testing; testing run-tests --path tests/'

use std assert
use ../package/scripts/nu-nix/mod.nu *


# ── Primitives ────────────────────────────────────────────────────────────────

#[test]
def "test null" [] {
  assert equal (null | to nix) "null"
}

#[test]
def "test bool true" [] {
  assert equal (true | to nix) "true"
}

#[test]
def "test bool false" [] {
  assert equal (false | to nix) "false"
}

#[test]
def "test int" [] {
  assert equal (42 | to nix) "42"
}

#[test]
def "test negative int" [] {
  assert equal (-5 | to nix) "-5"
}

#[test]
def "test zero" [] {
  assert equal (0 | to nix) "0"
}

#[test]
def "test float" [] {
  assert equal (3.14 | to nix) "3.14"
}

#[test]
def "test float whole gets dot zero" [] {
  # Nushell may serialise 1.0 as "1"; we must emit "1.0" so Nix sees a float.
  assert ($"(1.0 | to nix)" | str contains ".")
}


# ── Strings ───────────────────────────────────────────────────────────────────

#[test]
def "test string plain" [] {
  assert equal ("hello" | to nix) '"hello"'
}

#[test]
def "test string empty" [] {
  assert equal ("" | to nix) '""'
}

#[test]
def "test string backslash" [] {
  # A single backslash in Nu becomes \\ in the Nix string literal.
  assert equal ('a\b' | to nix) '"a\\b"'
}

#[test]
def "test string double quote" [] {
  # Double quotes are escaped with \".
  assert equal ('say "hi"' | to nix) '"say \"hi\""'
}

#[test]
def "test string newline" [] {
  # An actual newline character becomes the \n escape sequence.
  let s = $"line1(char newline)line2"
  assert equal ($s | to nix) '"line1\nline2"'
}

#[test]
def "test string tab" [] {
  let s = $"a(char tab)b"
  assert equal ($s | to nix) '"a\tb"'
}

#[test]
def "test string carriage return" [] {
  let s = $"a(char cr)b"
  assert equal ($s | to nix) '"a\rb"'
}

#[test]
def "test string antiquote" [] {
  # ${...} inside a Nix string triggers antiquotation; escape it as \${...}.
  # Single-quoted Nu strings are raw, so '${HOME}' is the literal 7 chars ${HOME}.
  assert equal ('${HOME}' | to nix) '"\${HOME}"'
}


# ── Lists ─────────────────────────────────────────────────────────────────────

#[test]
def "test empty list" [] {
  assert equal ([] | to nix) "[ ]"
}

#[test]
def "test int list" [] {
  assert equal ([1 2 3] | to nix) "[\n  1\n  2\n  3\n]"
}

#[test]
def "test string list" [] {
  assert equal (["a" "b"] | to nix) "[\n  \"a\"\n  \"b\"\n]"
}

#[test]
def "test mixed-type list" [] {
  assert equal ([true 1 "x"] | to nix) "[\n  true\n  1\n  \"x\"\n]"
}

#[test]
def "test nested list" [] {
  assert equal ([[1 2] [3 4]] | to nix) "[\n  [\n    1\n    2\n  ]\n  [\n    3\n    4\n  ]\n]"
}


# ── Records ───────────────────────────────────────────────────────────────────

#[test]
def "test empty record" [] {
  assert equal ({} | to nix) "{ }"
}

#[test]
def "test simple record" [] {
  assert equal ({a: 1} | to nix) "{\n  a = 1;\n}"
}

#[test]
def "test record hyphen key is bare" [] {
  # foo-bar is a valid Nix identifier; it must NOT be quoted.
  assert equal ({foo-bar: 1} | to nix) "{\n  foo-bar = 1;\n}"
}

#[test]
def "test record space key is quoted" [] {
  assert ({"hello world": 1} | to nix | str contains '"hello world" = 1;')
}

#[test]
def "test record nested" [] {
  assert equal ({a: {b: 1}} | to nix) "{\n  a = {\n    b = 1;\n  };\n}"
}

#[test]
def "test record multiple fields" [] {
  let r = ({x: 1, y: 2} | to nix)
  assert ($r | str contains "x = 1;")
  assert ($r | str contains "y = 2;")
}

#[test]
def "test record with list value" [] {
  let r = ({tags: ["a" "b"]} | to nix)
  assert ($r | str contains "tags =")
  assert ($r | str contains '"a"')
}


# ── Attrset key edge cases ────────────────────────────────────────────────────

#[test]
def "test key with apostrophe is bare" [] {
  # Apostrophes are allowed after the first character in Nix identifiers.
  assert equal ({"foo'": 1} | to nix) "{\n  foo' = 1;\n}"
}

#[test]
def "test key starting with digit is quoted" [] {
  # Nix identifiers cannot start with a digit.
  assert ({"1foo": 1} | to nix | str contains '"1foo" = 1;')
}

#[test]
def "test key of only digits is quoted" [] {
  assert ({"42": 1} | to nix | str contains '"42" = 1;')
}

#[test]
def "test empty string key is quoted" [] {
  assert ({"": 1} | to nix | str contains '"" = 1;')
}


# ── Nu types with no Nix equivalent ──────────────────────────────────────────

#[test]
def "test datetime becomes iso8601 string" [] {
  # Nix has no date type; we emit an ISO-8601 string.
  let r = (2024-01-15 | to nix)
  assert ($r | str starts-with '"')
  assert ($r | str contains "2024-01-15")
}

#[test]
def "test filesize becomes bytes as int" [] {
  # Nix has no filesize type; we emit the raw byte count.
  assert equal (1kb  | to nix) "1000"    # SI:  1 kB  = 1 000 bytes
  assert equal (1kib | to nix) "1024"    # IEC: 1 KiB = 1 024 bytes
  assert equal (1mib | to nix) "1048576"
}

#[test]
def "test duration becomes nanoseconds as int" [] {
  # Nix has no duration type; we emit nanoseconds.
  assert equal (1sec | to nix) "1000000000"
  assert equal (1ms  | to nix) "1000000"
}


# ── Binary ────────────────────────────────────────────────────────────────────
# Nix has no binary/bytes type.  `to nix` errors and suggests two workarounds:
#   encode base64 | to nix
#     → a Nix string (decode with pkgs.lib.base64Decode on the Nix side)
#   encode hex | split chars | chunks 2 | each { str join | into int --radix 16 } | to nix
#     → a Nix list of byte values [65 66 67]

#[test]
def "test binary errors" [] {
  assert error { 0x[41 42 43] | to nix }
}

#[test]
def "test binary base64 workaround" [] {
  assert equal (0x[41 42 43] | encode base64 | to nix) '"QUJD"'
}

#[test]
def "test binary byte-list workaround" [] {
  let bytes = (
    0x[41 42 43]
    | encode hex
    | split chars
    | chunks 2
    | each { str join | into int --radix 16 }
  )
  assert equal ($bytes | to nix) "[\n  65\n  66\n  67\n]"
}


# ── Numeric edge cases ────────────────────────────────────────────────────────

#[test]
def "test large positive int" [] {
  assert equal (9007199254740992 | to nix) "9007199254740992"
}

#[test]
def "test large negative int" [] {
  assert equal (-9007199254740992 | to nix) "-9007199254740992"
}

#[test]
def "test negative float" [] {
  assert equal (-3.14 | to nix) "-3.14"
}


# ── Tables ────────────────────────────────────────────────────────────────────

#[test]
def "test table becomes list of attrsets" [] {
  let t = [[name version]; ["hello" "2.12"] ["gcc" "14.1"]]
  let r = ($t | to nix)
  assert ($r | str starts-with "[")
  assert ($r | str contains 'name = "hello"')
  assert ($r | str contains 'version = "14.1"')
}


# ── Realistic examples ────────────────────────────────────────────────────────

#[test]
def "test nixos-style service config" [] {
  let cfg = {
    services: {nginx: {enable: true, port: 80}}
    networking: {hostName: "myhost", firewall: {enable: true, allowedTCPPorts: [80 443]}}
  }
  let r = ($cfg | to nix)
  assert ($r | str contains "nginx =")
  assert ($r | str contains "enable = true;")
  assert ($r | str contains "hostName =")
  assert ($r | str contains "allowedTCPPorts =")
}

#[test]
def "test package meta record" [] {
  let meta = {pname: "hello", version: "2.12", broken: false, description: "A friendly greeting"}
  let r = ($meta | to nix)
  assert ($r | str contains 'pname = "hello"')
  assert ($r | str contains "broken = false")
  assert ($r | str contains 'description = "A friendly greeting"')
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

let _results = [
  # Primitives
  (_run "null"                        { test null })
  (_run "bool true"                   { test bool true })
  (_run "bool false"                  { test bool false })
  (_run "int"                         { test int })
  (_run "negative int"                { test negative int })
  (_run "zero"                        { test zero })
  (_run "float"                       { test float })
  (_run "float whole gets dot zero"   { test float whole gets dot zero })

  # Strings
  (_run "string plain"                { test string plain })
  (_run "string empty"                { test string empty })
  (_run "string backslash"            { test string backslash })
  (_run "string double quote"         { test string double quote })
  (_run "string newline"              { test string newline })
  (_run "string tab"                  { test string tab })
  (_run "string carriage return"      { test string carriage return })
  (_run "string antiquote"            { test string antiquote })

  # Lists
  (_run "empty list"                  { test empty list })
  (_run "int list"                    { test int list })
  (_run "string list"                 { test string list })
  (_run "mixed-type list"             { test mixed-type list })
  (_run "nested list"                 { test nested list })

  # Records
  (_run "empty record"                { test empty record })
  (_run "simple record"               { test simple record })
  (_run "record hyphen key is bare"   { test record hyphen key is bare })
  (_run "record space key is quoted"  { test record space key is quoted })
  (_run "record nested"               { test record nested })
  (_run "record multiple fields"      { test record multiple fields })
  (_run "record with list value"      { test record with list value })

  # Attrset key edge cases
  (_run "key with apostrophe is bare"    { test key with apostrophe is bare })
  (_run "key starting with digit is quoted" { test key starting with digit is quoted })
  (_run "key of only digits is quoted"   { test key of only digits is quoted })
  (_run "empty string key is quoted"     { test empty string key is quoted })

  # Nu types with no Nix equivalent
  (_run "datetime becomes iso8601 string"  { test datetime becomes iso8601 string })
  (_run "filesize becomes bytes as int"    { test filesize becomes bytes as int })
  (_run "duration becomes nanoseconds"     { test duration becomes nanoseconds as int })

  # Binary
  (_run "binary errors"               { test binary errors })
  (_run "binary base64 workaround"    { test binary base64 workaround })
  (_run "binary byte-list workaround" { test binary byte-list workaround })

  # Numeric edge cases
  (_run "large positive int"          { test large positive int })
  (_run "large negative int"          { test large negative int })
  (_run "negative float"              { test negative float })

  # Tables
  (_run "table becomes list of attrsets" { test table becomes list of attrsets })

  # Realistic examples
  (_run "nixos-style service config"  { test nixos-style service config })
  (_run "package meta record"         { test package meta record })
]

let _n_pass = ($_results | where { $in } | length)
let _n_fail  = ($_results | where { not $in } | length)
print $"\n($_n_pass) passed, ($_n_fail) failed"
if $_n_fail > 0 { exit 1 }
