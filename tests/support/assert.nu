# Minimal test assertions kept local so the suite is not coupled to Nushell's
# evolving standard-library assertion API.
export def main [condition: bool, message?: string] {
  if not $condition {
    error make { msg: ($message | default "assertion failed") }
  }
}

export def equal [actual: any, expected: any, message?: string] {
  if $actual != $expected {
    error make {
      msg: ($message | default $"values are not equal\nactual:   ($actual | to nuon)\nexpected: ($expected | to nuon)")
    }
  }
}

export def error [action: closure, message?: string] {
  let failed = (try {
    do $action
    false
  } catch {
    true
  })
  if not $failed {
    error make { msg: ($message | default "expected an error") }
  }
}
