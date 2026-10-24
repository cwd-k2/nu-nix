use ./support/assert.nu

let value = (nix eval '{ answer = 40 + 2; nested = [ "ok" (throw "lazy failure") ]; }')

assert equal ($value | nix type) "a set"
assert equal ($value.answer | nix collect) 42
assert equal ($value.nested.0 | nix collect) "ok"
assert error { $value.nested.1 | nix collect }
assert equal ($value | to text | str trim) "<lazy Nix value>"
assert equal (nix eval '{ z = 1; a = 2; }' | nix attr names) [a z]
assert equal (nix eval '{ MixedCase = 42; }' | get --ignore-case mixedcase | nix collect) 42
assert equal (nix eval '{ Name = 1; name = 2; }' | get --ignore-case NAME | nix collect) 2
assert error { nix eval 'let value = { self = value; }; in value' | nix collect }
let invalid_utf8 = ($nu.temp-dir | path join $"nu-nix-invalid-utf8-(random uuid)")
0x[ff] | save $invalid_utf8
assert error {
  nix eval $"builtins.readFile ./($invalid_utf8 | path basename)" --path $nu.temp-dir
  | nix collect
}
rm $invalid_utf8
assert equal (
  nix eval '{ enabled = true; items = [ 1 2 3 ]; }' | nix collect
) {
  enabled: true
  items: [1 2 3]
}
assert equal ((
  nix eval '"${builtins.toFile "native-realise" "ok"}"'
  | nix realise
  | path basename
) | str ends-with "-native-realise") true

let typed = ({
  enabled: true
  answer: 42
  nested: [null 1.5 "text"]
} | into nix)
assert equal ($typed | nix collect) {
  answer: 42
  enabled: true
  nested: [null 1.5 "text"]
}
assert equal ("." | into nix --path | nix type) "a path"
assert equal ("." | into nix --path | nix collect) (pwd | path expand)
assert error { 1kb | into nix }
assert error { 0x[01 02] | into nix }
assert error { $"before(char nul)after" | into nix }
assert error { [1 2] | into nix --path }
assert equal ([] | into nix | nix collect) []
assert equal ({} | into nix | nix collect) {}

let add = (nix eval 'left: right: left + right')
assert equal ($add | nix call 20 22 | nix collect) 42
let select = (nix eval 'input: input.answer')
assert equal ($select | nix call {answer: 42} | nix collect) 42
let lazy = (nix eval 'input: input.ok')
let throwing_set = (nix eval '{ unused = throw "unused"; }')
assert equal ($lazy | nix call {ok: 42, unused: $throwing_set.unused} | nix collect) 42
assert error { (nix eval '1') | nix call 2 }

let contextual = (nix eval '"${builtins.toFile "native-context" "ok"}"')
let realised_details = ($contextual | nix realise --details)
assert equal $realised_details.value ($contextual | nix realise)
assert equal ($realised_details.storePaths | length) 1
assert equal $realised_details.storePaths.0.name native-context
assert equal ($realised_details.storePaths.0.hash | str length) 40
assert equal (($realised_details.physicalPaths.0 | path basename) | str ends-with "-native-context") true
assert equal (nix eval '"plain"' | nix realise --details).storePaths []

let policy_value = (nix eval '42')
let pure_status = (nix debug runtime status)
assert equal $pure_status.policy.locked false
assert equal $pure_status.capabilities.cancellation safe-abandon-and-reset
assert equal $pure_status.capabilities.progress false
nix eval '42' --store auto | ignore
let alternate_store_status = (nix debug runtime status)
assert equal $alternate_store_status.policy.store auto
assert equal $alternate_store_status.generation ($pure_status.generation + 1)
assert error { $policy_value | nix collect }
nix eval '42' | ignore

let before_drop = (nix debug runtime status).handles
do {
  let temporary = (42 | into nix)
  let alias = $temporary
  assert equal ($alias | nix collect) 42
  assert equal (nix debug runtime status).handles ($before_drop + 1)
} | ignore
assert equal (nix debug runtime status).handles $before_drop

let stale = (nix eval '42')
let old_generation = (nix debug runtime status).generation
nix debug runtime reset
assert equal (nix debug runtime status).initialized false
assert equal (nix debug runtime status).handles 0
assert equal (nix debug runtime status).generation ($old_generation + 1)
assert error { $stale | nix collect }
assert equal (nix debug runtime status).initialized false
assert equal (nix eval '6 * 7' | nix collect) 42

print "native Nix plugin passed"
