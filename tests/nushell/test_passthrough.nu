use ./support/assert.nu
use MODULE *

let dependency_tree = (nix why-depends /nix/store/example /nix/store/dependency)
assert equal $dependency_tree "native dependency tree\n"
assert error { nix why-depends unexpected }
assert equal (nix unsupported-command --flag value) "raw fallback: unsupported-command --flag value"
assert equal (nix) "raw fallback: root"
assert equal (^nix unsupported-command --flag value) "raw fallback: unsupported-command --flag value"
let fallback_failure = (nix unsupported-failure | complete)
assert equal $fallback_failure.exit_code 23
assert ($fallback_failure.stderr | str contains "raw fallback failure")

print "native Nix text pass-through passed"
