# nu-nix commands — structured Nix commands for Nushell pipelines.
#
# All commands are prefixed with `nu-nix` to distinguish them from the raw
# `nix` CLI.  After `use nu-nix *` these become first-class Nu pipeline
# commands that return tables and records rather than text.
#
# Shell-entry commands (develop / shell) start a child Nushell session inside
# the Nix environment and return to the current session when it exits.
#
# Raw nix pass-through:  ^nix <subcommand>  (external, text output)
# Nu-integrated:         nu-nix <subcommand> (this module, Nu values)

use internal.nu run-nix-json
use normalize.nu *

# ── Shell entry — enter a Nix environment with Nushell ───────────────────────

# Enter a nix develop shell running Nushell.
export def --wrapped "nu-nix develop" [...rest: string] {
  ^nix develop ...$rest --command $nu.current-exe
}

# Enter a nix shell running Nushell.
export def --wrapped "nu-nix shell" [...rest: string] {
  ^nix shell ...$rest --command $nu.current-exe
}

# ── Build ─────────────────────────────────────────────────────────────────────

# Build a derivation; return output paths as a table.
export def --wrapped "nu-nix build" [...rest: string] {
  run-nix-json build --json ...$rest | normalize-build
}

# ── Search and inspect ────────────────────────────────────────────────────────

# Search packages; return results as a table.
export def --wrapped "nu-nix search" [...rest: string] {
  run-nix-json search --json ...$rest | normalize-search
}

# Query store path info as a table.
export def --wrapped "nu-nix path-info" [...rest: string] {
  run-nix-json path-info --json --json-format 1 ...$rest | normalize-path-info
}

# Inspect every path in a store closure, including aggregate closure sizes.
export def --wrapped "nu-nix closure" [...rest: string] {
  run-nix-json path-info --json --json-format 1 --recursive --closure-size ...$rest | normalize-path-info
}

# Show derivation details as a table.
export def --wrapped "nu-nix derivation show" [...rest: string] {
  run-nix-json derivation show ...$rest | normalize-derivations
}

# Show dependency chain between two store paths.
export def --wrapped "nu-nix why-depends" [...rest: string] {
  run-nix-json why-depends --json ...$rest
}

# ── Dev environment ───────────────────────────────────────────────────────────

# Show build-time environment variables as a table.
export def --wrapped "nu-nix print-dev-env" [...rest: string] {
  run-nix-json print-dev-env --json ...$rest | normalize-dev-environment
}

# ── Flake ─────────────────────────────────────────────────────────────────────

# Show flake outputs as a table.
export def --wrapped "nu-nix flake show" [...rest: string] {
  run-nix-json flake show --json ...$rest | normalize-flake-show
}

# Show flake metadata as a record.
export def --wrapped "nu-nix flake metadata" [...rest: string] {
  run-nix-json flake metadata --json ...$rest
}

# ── Profile ───────────────────────────────────────────────────────────────────

# List installed profile packages as a table.
export def --wrapped "nu-nix profile list" [...rest: string] {
  run-nix-json profile list --json ...$rest | normalize-profile
}

# Compare two profile generations as structured data. With --closure, compare
# their complete store closures instead of only directly installed packages.
export def "nu-nix profile diff" [
  before: path  # older profile generation link
  after: path   # newer profile generation link
  --closure     # include every transitive store path
  --all         # include unchanged entries
] {
  let old_path = ($before | path expand | into string)
  let new_path = ($after | path expand | into string)
  if $closure {
    let old = (run-nix-json path-info --json --json-format 1 --recursive --closure-size $old_path)
    let new = (run-nix-json path-info --json --json-format 1 --recursive --closure-size $new_path)
    normalize-closure-diff $old $new --all=$all
  } else {
    let old = (run-nix-json profile list --json --profile $old_path)
    let new = (run-nix-json profile list --json --profile $new_path)
    normalize-profile-diff $old $new --all=$all
  }
}
