# nu-nix commands — structured Nix commands for Nushell pipelines.
#
# All commands are prefixed with `nu-nix` to distinguish them from the raw
# `nix` CLI.  After `use nu-nix *` these become first-class Nu pipeline
# commands that return tables and records rather than text.
#
# Shell-entry commands (develop / shell) exec into a new Nushell
# session inside the Nix environment; they do not return.
#
# Raw nix pass-through:  ^nix <subcommand>  (external, text output)
# Nu-integrated:         nu-nix <subcommand> (this module, Nu values)

# ── Internal helpers ──────────────────────────────────────────────────────────

def flake-description [info: any]: nothing -> string {
  if ($info | describe | str starts-with "record") {
    $info.description? | default ""
  } else { "" }
}

# ── Shell entry — exec into a Nix environment with Nushell ───────────────────

# Enter a nix develop shell running Nushell.
export def --wrapped "nu-nix develop" [...rest: string] {
  exec "nix" "develop" ...$rest "--command" $nu.current-exe
}

# Enter a nix shell running Nushell.
export def --wrapped "nu-nix shell" [...rest: string] {
  exec "nix" "shell" ...$rest "--command" $nu.current-exe
}

# ── Build ─────────────────────────────────────────────────────────────────────

# Build a derivation; return output paths as a table.
export def --wrapped "nu-nix build" [...rest: string] {
  ^nix build --json ...$rest
  | from json
  | each {|r|
      $r.outputs
      | transpose output path
      | insert drvPath $r.drvPath
    }
  | flatten
}

# ── Search and inspect ────────────────────────────────────────────────────────

# Search packages; return results as a table.
export def --wrapped "nu-nix search" [...rest: string] {
  ^nix search --json ...$rest
  | from json
  | transpose attr info
  | each {|r| $r.info | insert attr $r.attr }
  | select attr pname version description
}

# Query store path info as a table.
export def --wrapped "nu-nix path-info" [...rest: string] {
  ^nix path-info --json ...$rest
  | from json
  | transpose path info
  | each {|r| $r.info | insert path $r.path }
}

# Show derivation details as a table.
export def --wrapped "nu-nix derivation show" [...rest: string] {
  ^nix derivation show ...$rest
  | from json
  | transpose drv info
  | each {|r| $r.info | insert drv $r.drv }
}

# Show dependency chain between two store paths.
export def --wrapped "nu-nix why-depends" [...rest: string] {
  ^nix why-depends --json ...$rest | from json
}

# ── Dev environment ───────────────────────────────────────────────────────────

# Show build-time environment variables as a table.
export def --wrapped "nu-nix print-dev-env" [...rest: string] {
  ^nix print-dev-env --json ...$rest
  | from json
  | get variables
  | transpose name info
  | each {|r| $r.info | insert name $r.name }
}

# ── Flake ─────────────────────────────────────────────────────────────────────

# Show flake outputs as a table.
export def --wrapped "nu-nix flake show" [...rest: string] {
  let named_types = ["packages" "devShells" "apps" "checks" "legacyPackages"]

  ^nix flake show --json ...$rest
  | from json
  | transpose type_name type_content
  | each {|row|
      let is_system_indexed = (
        $row.type_content | columns | any {|k| $k =~ 'linux|darwin|freebsd|netbsd|openbsd'}
      )
      if $is_system_indexed and ($row.type_name in $named_types) {
        $row.type_content | transpose system outputs
        | each {|s|
            $s.outputs | transpose name info
            | each {|n|
                { type: $row.type_name  system: $s.system
                  name: $n.name  description: (flake-description $n.info) }
              }
          }
        | flatten
      } else if $is_system_indexed {
        $row.type_content | transpose system info
        | each {|s|
            { type: $row.type_name  system: $s.system
              name: null  description: (flake-description $s.info) }
          }
      } else {
        $row.type_content | transpose name info
        | each {|n|
            { type: $row.type_name  system: null
              name: $n.name  description: (flake-description $n.info) }
          }
      }
    }
  | flatten
}

# Show flake metadata as a record.
export def --wrapped "nu-nix flake metadata" [...rest: string] {
  ^nix flake metadata --json ...$rest | from json
}

# ── Profile ───────────────────────────────────────────────────────────────────

# List installed profile packages as a table.
export def --wrapped "nu-nix profile list" [...rest: string] {
  ^nix profile list --json ...$rest
  | from json
  | get elements
  | transpose name info
  | each {|r| $r.info | insert name $r.name }
}
