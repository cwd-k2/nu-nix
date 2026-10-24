use std/assert

def replace-file [path: path, replacements: record] {
  $replacements
  | transpose from to
  | reduce --fold (open --raw $path) {|replacement, contents|
      $contents | str replace --all $replacement.from $replacement.to
    }
  | save --force $path
}

def main [repo: path, workspace: path] {
  let source = ($repo | path expand)
  let target = ($workspace | path expand)
  let fixture = ($target | path join fixture)
  let malformed_fixture = ($target | path join malformed-fixture)
  let tests = ($target | path join tests)

  if ($target | path exists) {
    error make {msg: $"workspace already exists: ($target)"}
  }

  mkdir $target $tests ($tests | path join support)
  cp --recursive ($source | path join tests fixtures task-flake) $fixture
  cp --recursive ($source | path join tests fixtures malformed-task-flake) $malformed_fixture
  cp ($source | path join tests nushell test_tasks.nu) ($tests | path join test_tasks.nu)
  cp ($source | path join tests nushell support assert.nu) ($tests | path join support assert.nu)

  let system = (^nix eval --raw --impure --expr builtins.currentSystem | str trim)
  let package = (
    ^nix build --no-link --print-out-paths $"($source)#nu-nix"
    | str trim
  )
  replace-file ($tests | path join test_tasks.nu) {
    MODULE: ($package | path join share nushell nu-nix mod.nu)
    SYSTEM: $system
    MALFORMED_FIXTURE: $malformed_fixture
    FIXTURE: $fixture
  }
  replace-file ($fixture | path join flake.nix) {SYSTEM: $system}
  replace-file ($malformed_fixture | path join flake.nix) {SYSTEM: $system}
  for repository in [$fixture $malformed_fixture] {
    ^git -C $repository init --quiet
    ^git -C $repository config user.name nu-nix-tests
    ^git -C $repository config user.email nu-nix-tests@invalid
    ^git -C $repository add .
    ^git -C $repository commit --quiet --message fixture
  }

  let plugin = ($package | path join bin nu_plugin_nix)
  let test_script = ($tests | path join test_tasks.nu)
  ^$nu.current-exe --no-config-file --plugins $plugin $test_script

  assert (($env.NU_NIX_SKIP_NESTED_BUILDS? | default "") != "1")
  print "real Nix task realisation passed"
}
