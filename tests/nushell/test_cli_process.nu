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
assert equal $failure.msg "fixture nix failure" "Nix stderr must be preserved exactly"

let malformed = (try {
  run-nix-json malformed
  null
} catch {|error| $error })
assert equal $malformed.msg "nix returned malformed JSON" "malformed JSON needs boundary context"

print "Nix JSON process boundary passed"
