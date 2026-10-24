# Structured Nix commands for Nushell pipelines.
#
# After `use nu-nix *`, `nix` names the integrated Nushell command family.
# Unknown subcommands fall through to the raw CLI. Use `^nix` to require the
# raw executable even when an integrated command with the same name exists.
#
# Shell-entry commands (develop / shell) start a child Nushell session inside
# the Nix environment and return to the current session when it exits.
#
# Nu-integrated:         nix <subcommand>  (this module, Nu values)
# Other Nix commands:   nix <subcommand>   (raw external process/output)
# Force raw executable: ^nix <subcommand>  (external process/output)

use cli-process.nu [enabled-nix-options run-external-text run-nix-json]
use normalize.nu *
use completions.nu [complete-build complete-dev-shell complete-shell]

# Nushell selects the more specific integrated commands below first. Everything
# else retains the external Nix CLI's arguments, output, and exit behavior.
export def --wrapped nix [...rest: string] {
  ^nix ...$rest
}

# ── Shell entry — enter a Nix environment with Nushell ───────────────────────

# Enter a development shell through the external Nix CLI, running Nushell.
export def --wrapped "nix develop" [
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

# Enter a package shell through the external Nix CLI, running Nushell.
export def --wrapped "nix shell" [
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

# Build installables through the external Nix CLI; return output paths as a table.
export def --wrapped "nix build" [
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

# Search packages through the external Nix CLI; return results as a table.
export def --wrapped "nix search" [...rest: string] {
  run-nix-json search --json ...$rest | normalize-search
}

# Query store path info through the external Nix CLI; return a table.
export def --wrapped "nix path-info" [...rest: string@complete-build] {
  run-nix-json path-info --json --json-format 1 ...$rest | normalize-path-info
}

# Inspect a store closure through the external Nix CLI, including aggregate sizes.
export def --wrapped "nix closure" [...rest: string@complete-build] {
  run-nix-json path-info --json --json-format 1 --recursive --closure-size ...$rest | normalize-path-info
}

# Show derivation details through the external Nix CLI; return a table.
export def --wrapped "nix derivation show" [...rest: string] {
  run-nix-json derivation show ...$rest | normalize-derivations
}

# Show the external Nix CLI's dependency tree between two store paths.
# `nix why-depends` has no machine-readable output, so this command deliberately
# remains a text pass-through instead of pretending to return structured data.
export def --wrapped "nix why-depends" [...rest: string] {
  run-external-text nix why-depends ...$rest
}

# ── Dev environment ───────────────────────────────────────────────────────────

# Read a development environment through the external Nix CLI; return a table.
export def --wrapped "nix print-dev-env" [...rest: string] {
  run-nix-json print-dev-env --json ...$rest | normalize-dev-environment
}

# ── Flake ─────────────────────────────────────────────────────────────────────

# Show flake outputs through the external Nix CLI; return a table.
export def --wrapped "nix flake show" [...rest: string] {
  run-nix-json flake show --json ...$rest | normalize-flake-show
}

# Show flake metadata through the external Nix CLI; return a record.
export def --wrapped "nix flake metadata" [...rest: string] {
  run-nix-json flake metadata --json ...$rest
}

# ── Profile ───────────────────────────────────────────────────────────────────

# List profile packages through the external Nix CLI; return a table.
export def --wrapped "nix profile list" [...rest: string] {
  run-nix-json profile list --json ...$rest | normalize-profile
}

def profile-arguments [profile: path]: nothing -> list<string> {
  if $profile == null {
    []
  } else {
    [--profile ($profile | path expand | into string)]
  }
}

def profile-state [profile: path]: nothing -> table {
  let options = (profile-arguments $profile)
  run-nix-json profile list --json ...$options | normalize-profile
}

# Add installables to a Nix profile; return the resulting profile state.
export def --wrapped "nix profile add" [
  --profile: path  # profile path, defaults to the standard user profile
  ...rest: string@complete-build
] {
  let options = (profile-arguments $profile)
  run-external-text nix profile add ...$options ...$rest | ignore
  profile-state $profile
}

# Remove elements from a Nix profile; return the resulting profile state.
export def --wrapped "nix profile remove" [
  --profile: path  # profile path, defaults to the standard user profile
  ...rest: string
] {
  let options = (profile-arguments $profile)
  run-external-text nix profile remove ...$options ...$rest | ignore
  profile-state $profile
}

# Upgrade profile elements; return the resulting profile state.
export def --wrapped "nix profile upgrade" [
  --profile: path  # profile path, defaults to the standard user profile
  ...rest: string
] {
  let options = (profile-arguments $profile)
  run-external-text nix profile upgrade ...$options ...$rest | ignore
  profile-state $profile
}

# Roll back a Nix profile; return the resulting profile state.
export def --wrapped "nix profile rollback" [
  --profile: path  # profile path, defaults to the standard user profile
  ...rest: string
] {
  let options = (profile-arguments $profile)
  run-external-text nix profile rollback ...$options ...$rest | ignore
  profile-state $profile
}

# Show the external Nix CLI's profile history.
# Nix exposes no machine-readable history format, so this remains text.
export def "nix profile history" [
  --profile: path  # profile path, defaults to the standard user profile
]: nothing -> string {
  let options = (profile-arguments $profile)
  run-external-text nix profile history ...$options
}

# Compare profile generations using external Nix CLI data. With --closure, compare
# their complete store closures instead of only directly installed packages.
export def "nix profile diff" [
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
