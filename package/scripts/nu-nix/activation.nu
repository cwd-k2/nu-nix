# Apply a Nix development environment to the current Nushell session.

use internal.nu run-nix-json
use normalize.nu normalize-dev-activation

export def --env --wrapped "nu-nix activate" [...rest: string] {
  let environment = (run-nix-json print-dev-env --json ...$rest)
  let normalized = ($environment | normalize-dev-activation)
  let updates = (if "PATH" in ($normalized.updates | columns) {
    $normalized.updates
    | upsert PATH ($normalized.updates.PATH | append $env.PATH | uniq)
  } else {
    $normalized.updates
  })
  let previous = ($updates
    | columns
    | each {|name|
        {
          name: $name
          present: ($name in ($env | columns))
          value: ($env | get --optional $name)
        }
      })
  let stack = ($env.NU_NIX_ACTIVATION_STACK? | default [])

  load-env $updates
  $env.NU_NIX_ACTIVATION_STACK = ($stack | append {
    previous: $previous
    applied: ($updates | columns)
  })

  {
    applied: ($updates | columns)
    skipped: $normalized.skipped
    ignoredBashFunctions: ($environment.bashFunctions | columns)
  }
}

export def --env "nu-nix deactivate" [] {
  let stack = ($env.NU_NIX_ACTIVATION_STACK? | default [])
  if ($stack | is-empty) {
    error make { msg: "no nu-nix development environment is active" }
  }

  let activation = ($stack | last)
  for item in $activation.previous {
    if $item.present {
      load-env ({} | insert $item.name $item.value)
    } else {
      hide-env $item.name
    }
  }

  let remaining = ($stack | drop 1)
  if ($remaining | is-empty) {
    hide-env NU_NIX_ACTIVATION_STACK
  } else {
    $env.NU_NIX_ACTIVATION_STACK = $remaining
  }
}
