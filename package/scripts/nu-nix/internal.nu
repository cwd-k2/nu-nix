# Shared boundary for commands that consume Nix's machine-readable output.
export def --wrapped run-nix-json [...args: string]: nothing -> any {
  let result = (do { ^nix ...$args } | complete)
  if $result.exit_code != 0 {
    let message = ($result.stderr | str trim)
    error make {
      msg: (if ($message | is-empty) {
        $"nix exited with status ($result.exit_code)"
      } else {
        $message
      })
      help: $"command: nix ($args | str join ' ')"
    }
  }

  if not ($result.stderr | is-empty) {
    print --stderr --no-newline $result.stderr
  }

  try {
    $result.stdout | from json
  } catch {|parse_error|
    error make {
      msg: "nix returned malformed JSON"
      help: ($parse_error.msg? | default "check the selected Nix command's JSON output")
    }
  }
}
