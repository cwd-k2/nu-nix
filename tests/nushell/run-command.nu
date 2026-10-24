use std assert
use nu-nix *

assert ($env.NU_NIX_RUN_COMMAND_TEST == "native")
assert ((^hello | str trim) == "Hello, world!")
assert (({enabled: true} | to nix) == "{\n  enabled = true;\n}")
assert ((nix eval "40 + 2" | nix collect) == 42)

touch $env.out
