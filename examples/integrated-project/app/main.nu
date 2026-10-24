use nu-nix *
use example-context *
use example-environment *
use ./message.nu [get-message]
use ./report.nu [project-report]

def main [name: string = "world"] {
  project-report $name (get-message)
  | insert evaluated (nix eval "40 + 2" | nix collect)
  | to json --raw
}
