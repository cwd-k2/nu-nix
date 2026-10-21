use std assert
use nu-nix *

assert ($env.NU_NIX_RUN_COMMAND_TEST == "from-nix")
assert ((^hello | str trim) == "Hello, world!")
assert (({enabled: true} | to nix) == "{\n  enabled = true;\n}")

touch $env.out
