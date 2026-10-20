use ./support/assert.nu
use MODULE *

let original_path = $env.PATH
let original_home = $env.HOME
$env.NU_NIX_EXISTING = "before"

let first = (nu-nix activate fixture)
assert equal ($env.PATH | first 2) [
  "/nix/store/fixture-one/bin"
  "/nix/store/fixture-two/bin"
]
assert ($original_path | all {|entry| $entry in $env.PATH })
assert equal $env.NU_NIX_EXISTING "from-dev-environment"
assert equal $env.NU_NIX_NEW "new-value"
assert equal $env.HOME $original_home
assert ("HOME" in $first.skipped)
assert ("shellHook" in $first.skipped)
assert equal $first.ignoredBashFunctions ["fixtureHook"]

nu-nix activate fixture | ignore
nu-nix deactivate
assert equal $env.NU_NIX_EXISTING "from-dev-environment"
assert equal $env.NU_NIX_NEW "new-value"

nu-nix deactivate
assert equal $env.PATH $original_path
assert equal $env.NU_NIX_EXISTING "before"
assert ("NU_NIX_NEW" not-in ($env | columns))
assert ("NU_NIX_ACTIVATION_STACK" not-in ($env | columns))

assert error { nu-nix deactivate }
print "development environment activation passed"
