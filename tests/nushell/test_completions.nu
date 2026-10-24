use ./support/assert.nu
use MODULE *

let fixture = "FIXTURE"
let build_values = (
  $"nix build ($fixture)#"
  | commandline complete --detailed
  | get value
)
assert equal $build_values [
  $"($fixture)#alpha"
  $"($fixture)#beta"
  $"($fixture)#scope"
]

let nested_build_values = (
  $"nix build ($fixture)#scope."
  | commandline complete --detailed
  | get value
)
assert equal $nested_build_values [$"($fixture)#scope.gamma"]

let build_flags = (
  "nix build --"
  | commandline complete --detailed
  | get value
)
assert ("--no-link" in $build_flags)
assert ("--offline" in $build_flags)

let dev_values = (
  $"nix activate ($fixture)#"
  | commandline complete --detailed
  | get value
)
assert equal $dev_values [$"($fixture)#development"]

# Completion must not fetch or evaluate non-local references.
let remote = (
  "nix build github:example/project#"
  | commandline complete --detailed
)
assert ($remote | is-empty)

print "Nushell completions passed"
