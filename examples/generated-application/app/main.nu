use nu-nix *
use example-context *
use example-environment *
use ./message.nu [get-message]

def main [name: string = "world"] {
  {
    greeting: $"(get-message) ($name)"
    nix: ({enabled: true} | to nix)
    external: (^hello | str trim)
    configured: $env.NU_NIX_APPLICATION_TEST
    host: $host
    features: $features
    editor: $env.EDITOR
    example_path: $env.EXAMPLE_PATH
  } | to json --raw
}
