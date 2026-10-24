# Flake-backed task orchestration over native Nix values.

use system.nu current-nix-system
use task-plan.nu [task-set task-field validate-task plan-tasks]

def task-environment [action: any]: nothing -> record {
  let environment = ($action | get --optional environment)
  if ($environment | describe) == "nothing" {
    return {}
  }
  let names = ($environment | nix attr names)
  if "PATH" in $names {
    error make {msg: "task environment.PATH is reserved; use runtimeInputs"}
  }
  $names
  | reduce --fold {} {|name, result|
      $result | insert $name (($environment | get $name) | nix realise)
    }
}

def task-script [action: any, task_name: string]: nothing -> record {
  let descriptor = ($action | get --optional script)
  if ($descriptor | describe) == "nothing" {
    error make {msg: $"task `($task_name)` does not contain a script descriptor"}
  }
  let script_type = (task-field $descriptor type null)
  match $script_type {
    "file" => {
      let details = ($descriptor.path | nix realise --details)
      if ($details.physicalPaths | length) != 1 {
        error make {
          msg: $"task `($task_name)` script must refer to exactly one store path; got ($details.storePaths | to nuon)"
        }
      }
      let physical_root = ($details.physicalPaths | first)
      let store_name = ($physical_root | path basename)
      let root_marker = $"/($store_name)"
      let root_offset = ($details.value | str index-of $root_marker)
      if $root_offset < 0 {
        error make {msg: $"task `($task_name)` script path could not be mapped to its store path"}
      }
      let suffix_offset = $root_offset + ($root_marker | str length)
      let suffix = ($details.value | str substring $suffix_offset..)
      let suffix_components = ($suffix | split row "/" | where {not ($in | is-empty)})
      let invalid_suffix = (
        (($suffix | is-not-empty) and (not ($suffix | str starts-with "/")))
        or ($suffix_components | any {|component| $component in ["." ".."]})
      )
      if $invalid_suffix {
        error make {msg: $"task `($task_name)` script has an invalid store-relative path"}
      }
      let path = $"($physical_root)($suffix)"
      {type: "file", path: $path}
    }
    "inline" => {
      let source = (task-field $descriptor text null)
      if ($source | describe) != string {
        error make {msg: $"task `($task_name)` does not contain inline Nushell source"}
      }
      {type: "inline", source: $source}
    }
    _ => { error make {msg: $"task `($task_name)` has unsupported script type ($script_type)"} }
  }
}

def run-nushell-action [
  planned: record,
  requested_name: string,
  args: list<string>,
]: nothing -> list<any> {
  let task_name = $planned.name
  let action = ($planned.value | get action)
  let script = (task-script $action $task_name)
  let declared_path = ($action.path | nix realise)
  let task_environment = (task-environment $action)
  let declared_entries = ($declared_path
    | split row (char esep)
    | where {not ($in | is-empty)})
  let path = if ($declared_entries | is-empty) {
    # An OS PATH cannot encode zero entries: an empty string means the
    # current directory. Use a non-directory to prevent that fallback.
    ["/dev/null"]
  } else {
    $declared_entries
  }
  let task_args = if $task_name == $requested_name { $args } else { [] }
  with-env ($task_environment | upsert PATH $path) {
    run-task-script $task_name $script $task_args
  }
  []
}

def run-realise-action [planned: record]: nothing -> list<record> {
  let task_name = $planned.name
  let action = ($planned.value | get action)
  let targets = ($action | get targets)
  mut outputs = []
  for target_name in ($targets | nix attr names) {
    let realised = try {
      let details = (($targets | get $target_name) | nix realise --details)
      if ($details.storePaths | is-empty) {
        error make {msg: "realisation target has no Nix string context"}
      }
      $details
    } catch {|error|
      error make {
        msg: $"task `($task_name)` target `($target_name)` failed: ($error.msg)"
      }
    }
    $outputs = ($outputs | append {
      target: $target_name
      value: $realised.value
      storePaths: $realised.storePaths
      physicalPaths: $realised.physicalPaths
    })
  }
  $outputs
}

def run-task-action [
  planned: record,
  requested_name: string,
  args: list<string>,
]: nothing -> list<any> {
  match $planned.action {
    "nushell" => (run-nushell-action $planned $requested_name $args)
    "realise" => (run-realise-action $planned)
    $action => { error make {msg: $"task `($planned.name)` has unsupported action type ($action)"} }
  }
}

def run-task-script [task_name: string, script: record, args: list<string>] {
  let outcome = try {
    # Nushell leaves LAST_EXIT_CODE unchanged after a successful external
    # command, so a previous unrelated failure must not leak into this task.
    $env.LAST_EXIT_CODE = 0
    if $script.type == "inline" {
      do --ignore-errors --env {
        ^$nu.current-exe --no-config-file --commands $script.source ...$args out> /dev/stderr
      }
    } else {
      do --ignore-errors --env {
        ^$nu.current-exe --no-config-file $script.path ...$args out> /dev/stderr
      }
    }
    {error: null, exit_code: ($env.LAST_EXIT_CODE? | default 0)}
  } catch {|error|
    {error: $error, exit_code: null}
  }
  if ($outcome.error | describe) != "nothing" {
    error make {
      msg: $"task `($task_name)` could not be executed: ($outcome.error.msg)"
    }
  }
  if $outcome.exit_code != 0 {
    error make {msg: $"task `($task_name)` failed with exit code ($outcome.exit_code)"}
  }
}

# List tasks declared by a flake under `tasks.<system>`.
export def "nix task list" [
  --flake: string = "."     # flake reference
  --base-path: path = .     # base for relative flake references
  --system: string          # target system, defaults to the current system
] {
  let selected_system = ($system | default (current-nix-system))
  let tasks = (task-set $flake $base_path $selected_system)
  $tasks
  | nix attr names
  | each {|name|
      validate-task ($tasks | get $name) $name
      | reject value
    }
}

# Run a task and its dependencies in dependency order.
export def --wrapped "nix task run" [
  name: string                # task name
  --flake: string = "."      # flake reference
  --base-path: path = .       # base for relative flake references
  --system: string            # target system, defaults to the current system
  --dry-run                   # return the execution plan without running it
  --report-errors             # return failed and skipped rows instead of raising
  ...args: string             # arguments passed to the requested task only
] {
  let selected_system = ($system | default (current-nix-system))
  if (not $dry_run) and $selected_system != (current-nix-system) {
    error make {
      msg: $"cannot run tasks for ($selected_system) on (current-nix-system)"
      help: "Use --dry-run to inspect a foreign-system plan."
    }
  }
  let tasks = (task-set $flake $base_path $selected_system)
  let plan = (plan-tasks $tasks $name)
  if $dry_run {
    return ($plan | select name action)
  }
  let root = ($plan | last)
  if $root.action == "realise" and (not ($args | is-empty)) {
    error make {msg: $"task `($name)` does not accept arguments"}
  }

  mut report = []
  mut failed_task = ""
  for planned in $plan {
    let task_name = $planned.name
    let action_type = $planned.action
    if (not ($failed_task | is-empty)) {
      $report = ($report | append {
        task: $task_name
        action: $action_type
        status: skipped
        outputs: []
        error: $"dependency task `($failed_task)` failed"
      })
      continue
    }
    let outcome = try {
      let outputs = (run-task-action $planned $name $args)
      {status: "succeeded", outputs: $outputs}
    } catch {|error|
      {status: "failed", outputs: [], error: $error.msg}
    }
    let row = {
      task: $task_name
      action: $action_type
      status: $outcome.status
      outputs: $outcome.outputs
      error: ($outcome.error? | default null)
    }
    $report = ($report | append $row)
    if $outcome.status == "failed" {
      $failed_task = $task_name
    }
  }
  if (not ($failed_task | is-empty)) and (not $report_errors) {
    let failure = ($report | where status == failed | first)
    error make {msg: $failure.error}
  }
  $report
}
