use ./support/assert.nu
use MODULE *

let dependency_tree = (nu-nix why-depends /nix/store/example /nix/store/dependency)
assert equal $dependency_tree "native dependency tree\n"
assert error { nu-nix why-depends unexpected }

print "native Nix text pass-through passed"
