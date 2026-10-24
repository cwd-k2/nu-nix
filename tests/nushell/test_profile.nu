use ./support/assert.nu
use MODULE *

let profile = ("PROFILE" | path expand)

let added = (nix profile add .#environment --profile $profile)
assert equal ($added | get name) [environment]
assert equal $added.0.version "1"

let upgraded = (nix profile upgrade environment --profile $profile)
assert equal $upgraded.0.version "2"

let rolled_back = (nix profile rollback --profile $profile)
assert equal $rolled_back.0.version "1"

let history = (nix profile history --profile $profile)
assert ($history | str contains "Version 2") "profile history must remain visible"

let removed = (nix profile remove environment --profile $profile)
assert equal $removed []

print "structured profile lifecycle passed"
