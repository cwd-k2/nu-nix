use ./support/assert.nu
use MODULE [enabled-nix-options run-nix-json]

assert equal (enabled-nix-options {
  "--first": true
  "--disabled": false
  "--last": true
}) ["--first" "--last"]

assert equal (run-nix-json success) {answer: 42}

let failure = (try {
  run-nix-json fail
  null
} catch {|error| $error })
assert ($failure != null) "non-zero exit must raise an error"
assert ($failure.msg | str contains "fixture nix failure") "Nix stderr must be preserved"

let malformed = (try {
  run-nix-json malformed
  null
} catch {|error| $error })
assert ($malformed != null) "malformed JSON must raise an error"
assert equal $malformed.msg "nix returned malformed JSON" "malformed JSON needs boundary context"

print "Nix JSON process boundary passed"
