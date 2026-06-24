#!@nushell@/bin/nu

const NIX = "@nix@"
const NU  = "@nushell@"

const CATEGORIES = [
  {label: "Nushell entry points",             cmds: ["develop", "shell", "nix-shell"]}
  {label: "Structured output (JSON → table)", cmds: ["build", "search", "path-info", "print-dev-env", "why-depends", "flake show", "flake metadata", "derivation show", "profile list"]}
  {label: "Legacy nix-* wrappers",            cmds: ["nix-build"]}
]

def flake-description [info: any] {
  if ($info | describe | str starts-with "record") { $info.description? | default "" } else { "" }
}

# Enter a nix develop shell with Nushell
def --wrapped "main develop" [...rest: string] {
  exec $"($NIX)/bin/nix" develop ...$rest --command $"($NU)/bin/nu"
}

# Enter a nix shell with Nushell
def --wrapped "main shell" [...rest: string] {
  exec $"($NIX)/bin/nix" shell ...$rest --command $"($NU)/bin/nu"
}

# Enter a legacy nix-shell with Nushell
def --wrapped "main nix-shell" [...rest: string] {
  exec $"($NIX)/bin/nix-shell" ...$rest --run $"($NU)/bin/nu"
}

# Build; return output paths as a table
def --wrapped "main build" [...rest: string] {
  ^$"($NIX)/bin/nix" build --json ...$rest
  | from json
  | each {|r|
      $r.outputs
      | transpose output path
      | insert drvPath $r.drvPath
    }
  | flatten
}

# Search packages; return results as a table
def --wrapped "main search" [...rest: string] {
  ^$"($NIX)/bin/nix" search --json ...$rest
  | from json
  | transpose attr info
  | each {|r| $r.info | insert attr $r.attr }
  | select attr pname version description
}

# Query store path info as a table
def --wrapped "main path-info" [...rest: string] {
  ^$"($NIX)/bin/nix" path-info --json ...$rest
  | from json
  | transpose path info
  | each {|r| $r.info | insert path $r.path }
}

# Show dev environment variables as a table
def --wrapped "main print-dev-env" [...rest: string] {
  ^$"($NIX)/bin/nix" print-dev-env --json ...$rest
  | from json
  | get variables
  | transpose name info
  | each {|r| $r.info | insert name $r.name }
}

# Show dependency chain between two store paths
def --wrapped "main why-depends" [...rest: string] {
  ^$"($NIX)/bin/nix" why-depends --json ...$rest | from json
}

# Show flake outputs as a table
def --wrapped "main flake show" [...rest: string] {
  let named_types = ["packages" "devShells" "apps" "checks" "legacyPackages"]

  ^$"($NIX)/bin/nix" flake show --json ...$rest
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
            | each {|n| {type: $row.type_name  system: $s.system  name: $n.name  description: (flake-description $n.info)}}
          }
        | flatten
      } else if $is_system_indexed {
        $row.type_content | transpose system info
        | each {|s| {type: $row.type_name  system: $s.system  name: null  description: (flake-description $s.info)}}
      } else {
        $row.type_content | transpose name info
        | each {|n| {type: $row.type_name  system: null  name: $n.name  description: (flake-description $n.info)}}
      }
    }
  | flatten
}

# Show flake metadata as a record
def --wrapped "main flake metadata" [...rest: string] {
  ^$"($NIX)/bin/nix" flake metadata --json ...$rest | from json
}

# Show derivation details as a table
def --wrapped "main derivation show" [...rest: string] {
  ^$"($NIX)/bin/nix" derivation show ...$rest
  | from json
  | transpose drv info
  | each {|r| $r.info | insert drv $r.drv }
}

# List profile packages as a table
def --wrapped "main profile list" [...rest: string] {
  ^$"($NIX)/bin/nix" profile list --json ...$rest
  | from json
  | get elements
  | transpose name info
  | each {|r| $r.info | insert name $r.name }
}

# Build using legacy nix-build; return output paths as a list
def --wrapped "main nix-build" [...rest: string] {
  ^$"($NIX)/bin/nix-build" ...$rest | lines
}

# Pass unknown subcommands through to `nix <cmd>` or `nix-<cmd>`
def --wrapped main [...args: string] {
  match ($args | first | default "") {
    "" | "-h" | "--help" | "help" => {
      let cmds = scope commands
        | where name =~ "^main "
        | update name {|r| $r.name | str replace --regex "^main " ""}
        | select name description

      for $cat in $CATEGORIES {
        print $"(ansi default_bold)($cat.label)(ansi reset)"
        $cat.cmds
        | each {|c| $cmds | where name == $c | get 0? }
        | compact
        | update name {|r| $"nu-nix ($r.name)"}
        | table --index false
        | print
        print ""
      }
      exit 0
    }
    _ => {}
  }
  let subcommand = ($args | first)
  let rest = ($args | skip 1)
  if ($subcommand | str starts-with "nix-") {
    exec $"($NIX)/bin/($subcommand)" ...$rest
  } else {
    exec $"($NIX)/bin/nix" $subcommand ...$rest
  }
}
