use ./support/assert.nu
use MODULE *

let dependency_tree = (nu-nix why-depends /nix/store/example /nix/store/dependency | str trim)
assert equal $dependency_tree "native dependency tree"

print "native Nix text pass-through passed"
