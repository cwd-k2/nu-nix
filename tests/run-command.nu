use std assert
use nu-nix *

assert equal $env.NU_NIX_RUN_COMMAND_TEST "from-nix"
assert equal (^hello | str trim) "Hello, world!"
assert ({enabled: true} | to nix | str contains "enabled = true;")

touch $env.out
