# Runtime inventory for the integrated Nix command family.

const evaluator_commands = [
  "nix attr names"
  "nix call"
  "nix collect"
  "nix eval"
  "nix flake outputs"
  "nix realise"
  "nix type"
]

# List the currently registered integrated commands.
#
# The inventory comes from Nushell's command registry, so plugin and module
# commands cannot silently drift from this view. Evaluator diagnostics are
# grouped separately from normal workflows.
export def "nix commands" []: nothing -> table {
  scope commands
  | where {|command| $command.name | str starts-with "nix "}
  | each {|command|
      let group = if ($command.name | str starts-with "nix debug ") {
        "diagnostic"
      } else if $command.name in $evaluator_commands {
        "evaluator"
      } else if ($command.name | str starts-with "nix task ") {
        "task"
      } else if ($command.name | str starts-with "nix export ") {
        "export"
      } else if ($command.name | str starts-with "nix publication ") {
        "publication"
      } else {
        "workflow"
      }
      {
        group: $group
        command: $command.name
        description: $command.description
      }
    }
  | sort-by group command
}
