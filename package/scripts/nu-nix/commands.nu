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

use internal.nu [enabled-nix-options run-external-text run-nix-json]
use normalize.nu *
use completions.nu [complete-build complete-dev-shell complete-shell]

# ── Shell entry — enter a Nix environment with Nushell ───────────────────────

# Enter a nix develop shell running Nushell.
export def --wrapped "nu-nix develop" [
  --offline  # disable substituters and network access
  --impure   # allow access to mutable paths
  --refresh  # refresh cached flake inputs
  ...rest: string@complete-dev-shell
] {
  let options = (enabled-nix-options {
    "--offline": $offline
    "--impure": $impure
    "--refresh": $refresh
  })
  ^nix develop ...$options ...$rest --command $nu.current-exe
}

# Enter a nix shell running Nushell.
export def --wrapped "nu-nix shell" [
  --offline  # disable substituters and network access
  --impure   # allow access to mutable paths
  --refresh  # refresh cached flake inputs
  ...rest: string@complete-shell
] {
  let options = (enabled-nix-options {
    "--offline": $offline
    "--impure": $impure
    "--refresh": $refresh
  })
  ^nix shell ...$options ...$rest --command $nu.current-exe
}

# ── Build ─────────────────────────────────────────────────────────────────────

# Build a derivation; return output paths as a table.
export def --wrapped "nu-nix build" [
  --no-link  # do not create the result symlink
  --rebuild  # build again and compare the result
  --offline  # disable substituters and network access
  --impure   # allow access to mutable paths
  --refresh  # refresh cached flake inputs
  ...rest: string@complete-build
] {
  let options = (enabled-nix-options {
    "--no-link": $no_link
    "--rebuild": $rebuild
    "--offline": $offline
    "--impure": $impure
    "--refresh": $refresh
  })
  run-nix-json build --json ...$options ...$rest | normalize-build
}

# ── Search and inspect ────────────────────────────────────────────────────────

# Search packages; return results as a table.
export def --wrapped "nu-nix search" [...rest: string] {
  run-nix-json search --json ...$rest | normalize-search
}

# Query store path info as a table.
export def --wrapped "nu-nix path-info" [...rest: string@complete-build] {
  run-nix-json path-info --json --json-format 1 ...$rest | normalize-path-info
}

# Inspect every path in a store closure, including aggregate closure sizes.
export def --wrapped "nu-nix closure" [...rest: string@complete-build] {
  run-nix-json path-info --json --json-format 1 --recursive --closure-size ...$rest | normalize-path-info
}

# Show derivation details as a table.
export def --wrapped "nu-nix derivation show" [...rest: string] {
  run-nix-json derivation show ...$rest | normalize-derivations
}

# Show Nix's native dependency tree between two store paths.
# `nix why-depends` has no machine-readable output, so this command deliberately
# remains a text pass-through instead of pretending to return structured data.
export def --wrapped "nu-nix why-depends" [...rest: string] {
  run-external-text nix why-depends ...$rest
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
