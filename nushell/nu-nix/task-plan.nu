# Task discovery, schema validation, and dependency planning.
#
# This module is internal to nu-nix. Keeping planning separate from execution
# makes the no-effects-before-validation contract explicit.

use flake-output.nu flake-system-output

export def task-set [reference: string, base_path: path, system: string]: nothing -> any {
  flake-system-output $reference $base_path tasks $system
}

export def task-field [task: any, name: string, fallback: any]: nothing -> any {
  let value = ($task | get --optional $name)
  if ($value | describe) == "nothing" {
    $fallback
  } else {
    $value | nix collect
  }
}

def require-list-of-strings [value: any, field: string, task_name: string] {
  if (not (($value | describe) | str starts-with "list")) {
    error make {msg: $"task `($task_name)` ($field) must be a list of strings"}
  }
  if ($value | any {|item| ($item | describe) != "string"}) {
    error make {msg: $"task `($task_name)` ($field) must contain only strings"}
  }
}

def require-nix-string [value: any, field: string, task_name: string] {
  if ($value | describe) == "nothing" {
    error make {msg: $"task `($task_name)` ($field) must be a Nix string"}
  }
  let value_type = (try { $value | nix type } catch { null })
  if (not (($value_type | default "") | str starts-with "a string")) {
    error make {msg: $"task `($task_name)` ($field) must be a Nix string"}
  }
}

export def validate-task [task: any, task_name: string]: nothing -> record {
  let task_type = (task-field $task type null)
  if $task_type != "nu-nix-task" {
    error make {msg: $"task `($task_name)` has unsupported type ($task_type)"}
  }
  let version = (task-field $task version null)
  if $version != 2 {
    error make {msg: $"task `($task_name)` has unsupported schema version ($version)"}
  }
  let description = (task-field $task description "")
  if ($description | describe) != "string" {
    error make {msg: $"task `($task_name)` description must be a string"}
  }
  let deps = (task-field $task deps [])
  require-list-of-strings $deps deps $task_name

  let action = ($task | get --optional action)
  if ($action | describe) == "nothing" or ($action | nix type) != "a set" {
    error make {msg: $"task `($task_name)` action must be an attribute set"}
  }
  let action_type = (task-field $action type null)
  match $action_type {
    "nushell" => {
      require-nix-string ($action | get --optional path) action.path $task_name
      let environment = ($action | get --optional environment)
      if ($environment | describe) != "nothing" {
        if ($environment | nix type) != "a set" {
          error make {msg: $"task `($task_name)` action.environment must be an attribute set"}
        }
        let names = ($environment | nix attr names)
        if "PATH" in $names {
          error make {msg: "task environment.PATH is reserved; use runtimeInputs"}
        }
        for name in $names {
          require-nix-string ($environment | get $name) $"action.environment.($name)" $task_name
        }
      }
      let descriptor = ($action | get --optional script)
      if ($descriptor | describe) == "nothing" or ($descriptor | nix type) != "a set" {
        error make {msg: $"task `($task_name)` action.script must be an attribute set"}
      }
      let script_type = (task-field $descriptor type null)
      match $script_type {
        "file" => {
          require-nix-string ($descriptor | get --optional path) action.script.path $task_name
        }
        "inline" => {
          if ((task-field $descriptor text null) | describe) != "string" {
            error make {msg: $"task `($task_name)` action.script.text must be a string"}
          }
        }
        _ => { error make {msg: $"task `($task_name)` has unsupported script type ($script_type)"} }
      }
    }
    "realise" => {
      let targets = ($action | get --optional targets)
      if ($targets | describe) == "nothing" or ($targets | nix type) != "a set" {
        error make {msg: $"task `($task_name)` action.targets must be an attribute set"}
      }
      let names = ($targets | nix attr names)
      if ($names | is-empty) {
        error make {msg: $"task `($task_name)` action.targets must not be empty"}
      }
      for name in $names {
        require-nix-string ($targets | get $name) $"action.targets.($name)" $task_name
      }
    }
    _ => { error make {msg: $"task `($task_name)` has unsupported action type ($action_type)"} }
  }
  {
    name: $task_name
    description: $description
    deps: $deps
    action: $action_type
    value: $task
  }
}

def visit-task [
  tasks: any,
  task_names: list<string>,
  name: string,
  stack: list<string>,
  state: record,
]: nothing -> record {
  if $name in $stack {
    error make {msg: $"task dependency cycle: (($stack | append $name) | str join ' -> ')"}
  }
  if $name in $state.seen {
    return $state
  }
  if $name not-in $task_names {
    error make {msg: $"unknown task `($name)`"}
  }

  let validated = (validate-task ($tasks | get $name) $name)
  let resolved = ($validated.deps | reduce --fold $state {|dep, current|
    visit-task $tasks $task_names $dep ($stack | append $name) $current
  })
  {
    seen: ($resolved.seen | append $name)
    plan: ($resolved.plan | append $validated)
  }
}

# Return a fully validated, deterministic execution plan. Each task is
# validated once and shared dependencies appear once.
export def plan-tasks [tasks: any, root: string]: nothing -> list<record> {
  let task_names = ($tasks | nix attr names)
  (visit-task $tasks $task_names $root [] {seen: [], plan: []}).plan
}
