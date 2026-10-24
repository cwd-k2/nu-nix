use ./support/assert.nu
use MODULE *

let original_path = $env.PATH
let original_home = $env.HOME
$env.NU_NIX_EXISTING = "before"

let first = (nix activate fixture)
assert equal $env.PATH ([
  "/nix/store/fixture-one/bin"
  "/nix/store/fixture-two/bin"
] | append $original_path | uniq)
assert equal $env.NU_NIX_EXISTING "from-dev-environment"
assert equal $env.NU_NIX_NEW "new-value"
assert equal $env.HOME $original_home
assert equal $first {
  applied: ["PATH" "NU_NIX_EXISTING" "NU_NIX_NEW"]
  skipped: ["NU_NIX_ACTIVATION_STACK" "HOME" "shellHook"]
  ignoredBashFunctions: ["fixtureHook"]
}

nix activate fixture | ignore
nix deactivate
assert equal $env.NU_NIX_EXISTING "from-dev-environment"
assert equal $env.NU_NIX_NEW "new-value"

nix deactivate
assert equal $env.PATH $original_path
assert equal $env.NU_NIX_EXISTING "before"
assert ("NU_NIX_NEW" not-in ($env | columns))
assert ("NU_NIX_ACTIVATION_STACK" not-in ($env | columns))

assert error { nix deactivate }
print "development environment activation passed"
