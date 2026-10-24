use std/assert

def main [repo: path, workspace: path] {
  let source = ($repo | path expand)
  let target = ($workspace | path expand)
  let fixture = ($source | path join tests consumer profile-lifecycle)
  let profile = ($target | path join profile)

  if ($target | path exists) {
    error make { msg: $"workspace already exists: ($target)" }
  }

  cp --recursive $fixture $target
  open ($target | path join flake.nix)
  | str replace --all __NU_NIX_SOURCE__ ($source | into string)
  | save --force ($target | path join flake.nix)

  cd $target
  ^nix profile add path:. --profile $profile

  let launcher = ($profile | path join bin lifecycle-session)
  let installed = (^nix profile list --json --profile $profile | from json)
  assert (($installed.elements | columns | length) == 1)
  assert equal (^$launcher --no-config-file --commands demo | str trim) "1"

  "2\n" | save --force version
  ^nix profile upgrade --all --profile $profile --refresh
  assert equal (^$launcher --no-config-file --commands demo | str trim) "2"

  ^nix profile rollback --profile $profile
  assert equal (^$launcher --no-config-file --commands demo | str trim) "1"

  ^nix profile remove --all --profile $profile
  let removed = (^nix profile list --json --profile $profile | from json)
  assert ($removed.elements | is-empty)
  assert (not ($launcher | path exists))

  ^nix profile rollback --profile $profile
  assert equal (^$launcher --no-config-file --commands demo | str trim) "2"

  print "real Nix profile lifecycle passed"
}
