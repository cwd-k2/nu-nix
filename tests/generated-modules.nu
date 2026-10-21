use std assert
use VALUE_MODULE *
use ENV_MODULE *

assert ($answer == 42)
assert ($nested == {
  enabled: true
  items: ["quoted \"value\"", "line\nbreak", null]
})
assert ($empty == {})
assert ($env.NU_NIX_GENERATED == "configured")
assert ($env.NU_NIX_TYPED == [1 2 3])
assert ($env.NU_NIX_TEST_PATH == ["/first", "/shared", "/existing", "/duplicate", "/duplicate"])
assert ($env.NU_NIX_APPEND_PATH == ["/existing", "/duplicate", "/duplicate", "/shared", "/last"])
