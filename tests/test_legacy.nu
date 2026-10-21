use ./support/assert.nu
use MODULE *

assert equal (nu-nix-build example) [
  "/nix/store/example-one"
  "/nix/store/example-two"
]
assert error { nu-nix-build fail }

assert equal (nu-nix-channel list) [
  {name: "first", url: "https://example.test/first"}
  {name: "second", url: "https://example.test/second"}
]

assert equal (nu-nix-prefetch-url https://example.test/source) "sha256-prefetched"
assert equal (nu-nix-hash ./fixture) "sha256-hashed"

print "legacy Nix wrappers passed"
