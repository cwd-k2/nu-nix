# Context-aware completions for free-form Nix command arguments.

use system.nu current-nix-system

export def format-flake-completions [
  token: string
  outputs: table
  allowed_types: list<string>
]: nothing -> table {
  let parts = ($token | split row "#")
  let reference = ($parts | first)
  let fragment = ($parts | skip 1 | str join "#")
  $outputs
  | where {|row|
      ($row.type in $allowed_types) and ($row.name != null) and ($row.name | str starts-with $fragment)
    }
  | each {|row|
      let details = ([$row.kind $row.system $row.description]
        | where {|part| $part != null and (not ($part | is-empty)) }
        | str join " · ")
      {
        value: $"($reference)#($row.name)"
        description: $details
      }
    }
  | uniq-by value
}

def completion-token [input: any]: nothing -> string {
  if ($input | describe | str starts-with "record") {
    $input.text
  } else {
    $input | split row --regex '\s+' | last
  }
}

def local-output-rows [
  target: string
  output_type: string
  system: string
  parent: list<string>
]: nothing -> table {
  let output_path = ([ $output_type $system ] | append $parent | str join ".")
  let names = (try {
    ^nix --quiet eval --offline --no-write-lock-file --json $"($target)#($output_path)" --apply builtins.attrNames
    | from json
  } catch {
    []
  })
  $names | each {|name|
    {
      type: $output_type
      system: $system
      name: ($parent | append $name | str join ".")
      kind: null
      description: ""
    }
  }
}

def complete-local-flake [input: any, allowed_types: list<string>] {
  let token = (completion-token $input)
  if $token starts-with "-" {
    []
  } else if not ($token | str contains "#") {
    null
  } else {
    let reference = ($token | split row "#" | first)
    let target = if ($reference | is-empty) { "." } else { $reference }
    if not ($target | path exists) {
      # Never start a remote fetch merely because completion was requested.
      []
    } else {
      let system = (current-nix-system)
      let fragment = ($token | split row "#" | skip 1 | str join "#")
      let fragment_parts = ($fragment | split row ".")
      let parent = ($fragment_parts | drop 1)
      let outputs = ($allowed_types
        | each {|output_type| local-output-rows $target $output_type $system $parent }
        | flatten)
      format-flake-completions $token $outputs $allowed_types
    }
  }
}

export def complete-build [token: any] {
  complete-local-flake $token ["packages"]
}

export def complete-dev-shell [token: any] {
  complete-local-flake $token ["devShells"]
}

export def complete-shell [token: any] {
  complete-local-flake $token ["packages"]
}

export def complete-nix-value [token: any] {
  complete-local-flake $token ["packages"]
}
