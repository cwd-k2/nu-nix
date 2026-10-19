use nu-nix *
use ./message.nu [get-message]

def main [name: string = "world"] {
  {
    greeting: $"(get-message) ($name)"
    nix: ({enabled: true} | to nix)
    external: (^hello | str trim)
    configured: $env.NU_NIX_APPLICATION_TEST
  } | to json --raw
}
