use std/assert
use ./helper.nu task-message

def main [...args: string] {
  assert equal $env.NU_NIX_TASK_FROM_FLAKE "configured"
  assert ($env.NU_NIX_CONTEXT | path basename | str ends-with "-nu-nix-context")
  assert equal $env.PATH ["/dev/null"]
  $"(task-message):(($args | str join ',')):($env.NU_NIX_TASK_ARGUMENT)(char nl)"
  | save --append $env.NU_NIX_TASK_TEST_LOG
}
