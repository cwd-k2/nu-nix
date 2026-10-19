use std assert
use VALUE_MODULE *
use ENV_MODULE *

assert equal $answer 42
assert equal $nested {
  enabled: true
  items: ["quoted \"value\"", "line\nbreak", null]
}
assert equal $empty {}
assert equal $env.NU_NIX_GENERATED "configured"
assert equal $env.NU_NIX_TYPED [1 2 3]
assert equal $env.NU_NIX_TEST_PATH ["/first", "/shared", "/existing", "/duplicate", "/duplicate"]
assert equal $env.NU_NIX_APPEND_PATH ["/existing", "/duplicate", "/duplicate", "/shared", "/last"]
