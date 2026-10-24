# Process boundary for commands that consume Nix's machine-readable output.
export def enabled-nix-options [options: record]: nothing -> list<string> {
  $options
  | transpose option enabled
  | where enabled
  | get option
}

export def --wrapped run-external-text [command: string, ...args: string]: nothing -> string {
  let result = (do { run-external $command ...$args }
    | tee --stderr { save --append --raw /dev/stderr }
    | complete)
  if $result.exit_code != 0 {
    let message = ($result.stderr | str trim)
    error make {
      msg: (if ($message | is-empty) {
        $"($command) exited with status ($result.exit_code)"
      } else {
        $message
      })
      help: $"command: ($command) ($args | str join ' ')"
    }
  }

  $result.stdout
}

export def --wrapped run-nix-json [...args: string]: nothing -> any {
  let stdout = (run-external-text nix ...$args)

  try {
    $stdout | from json
  } catch {|parse_error|
    error make {
      msg: "nix returned malformed JSON"
      help: ($parse_error.msg? | default "check the selected Nix command's JSON output")
    }
  }
}
