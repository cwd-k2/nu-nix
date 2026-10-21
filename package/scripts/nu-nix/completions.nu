# Context-aware completions for free-form Nix command arguments.

const build_flags = [
  {value: "--no-link", description: "Do not create the result symlink"}
  {value: "--print-out-paths", description: "Print resulting store paths"}
  {value: "--rebuild", description: "Build again and compare the result"}
  {value: "--offline", description: "Disable substituters and network access"}
  {value: "--impure", description: "Allow access to mutable paths"}
  {value: "--refresh", description: "Refresh cached flake inputs"}
]

const shell_flags = [
  {value: "--ignore-environment", description: "Clear the environment before entering"}
  {value: "--keep", description: "Keep a variable with --ignore-environment"}
  {value: "--offline", description: "Disable substituters and network access"}
  {value: "--impure", description: "Allow access to mutable paths"}
  {value: "--refresh", description: "Refresh cached flake inputs"}
]

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

def local-output-rows [target: string, output_type: string, system: string]: nothing -> table {
  let names = (try {
    ^nix --quiet eval --json $"($target)#($output_type).($system)" --apply builtins.attrNames
    | from json
  } catch {
    []
  })
  $names | each {|name|
    {
      type: $output_type
      system: $system
      name: $name
      kind: null
      description: ""
    }
  }
}

def complete-local-flake [input: any, allowed_types: list<string>, flags: table] {
  let token = (completion-token $input)
  if $token starts-with "-" {
    $flags | where value starts-with $token
  } else if not ($token | str contains "#") {
    null
  } else {
    let reference = ($token | split row "#" | first)
    let target = if ($reference | is-empty) { "." } else { $reference }
    if not ($target | path exists) {
      # Never start a remote fetch merely because completion was requested.
      []
    } else {
      let system = $"($nu.os-info.arch)-($nu.os-info.name)"
      let outputs = ($allowed_types
        | each {|output_type| local-output-rows $target $output_type $system }
        | flatten)
      format-flake-completions $token $outputs $allowed_types
    }
  }
}

export def complete-build [token: any] {
  complete-local-flake $token ["packages"] $build_flags
}

export def complete-dev-shell [token: any] {
  complete-local-flake $token ["devShells"] $shell_flags
}

export def complete-shell [token: any] {
  complete-local-flake $token ["packages"] $shell_flags
}

export def complete-nix-value [token: any] {
  complete-local-flake $token ["packages"] []
}
