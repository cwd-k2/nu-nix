use ./support/assert.nu
use MODULE *

let fixture = ("FIXTURE" | path expand)
let malformed_fixture = ("MALFORMED_FIXTURE" | path expand)
let system = "SYSTEM"
let foreign_system = if $system == "x86_64-linux" { "aarch64-linux" } else { "x86_64-linux" }
let skip_nested_builds = (($env.NU_NIX_SKIP_NESTED_BUILDS? | default "") == "1")
let tasks = (nix task list --flake $fixture --base-path $fixture --system $system)
assert equal (
  nix flake outputs $'($fixture)#quoted."name.with.dots"' --base-path $fixture --locked
  | nix collect
) 42
let selected = (
  nix flake outputs $"($fixture)#tasks.($system).main" --base-path $fixture
)

let published_exports = (nix export list --flake $fixture --base-path $fixture --system $system)
assert equal ($published_exports | get name | sort) [add select]
assert equal (
  nix export inspect add --flake $fixture --base-path $fixture --system $system
  | select name description result
) {name: add, description: "Add two integers", result: collect}
assert equal (
  nix export call add --flake $fixture --base-path $fixture --system $system --arguments [20 22]
) 42
let selected_export = (
  nix export call select --flake $fixture --base-path $fixture --system $system --arguments [answer {answer: 42}]
)
assert equal ($selected_export | nix collect) 42
assert error {
  nix export call add --flake $fixture --base-path $fixture --system $system --arguments [1]
}
assert error {
  nix export inspect invalid --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert error {
  nix export inspect notFunction --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert equal (
  nix publication list --flake $fixture --base-path $fixture --system $system
  | select role name description entrypoint
) [{
  role: module
  name: example
  description: "Example generated module"
  entrypoint: main.nu
}]
assert equal (
  nix publication inspect module example --flake $fixture --base-path $fixture --system $system
  | select role name description entrypoint
) {role: module, name: example, description: "Example generated module", entrypoint: main.nu}
let resolved_publication = (
  nix publication resolve module example --flake $fixture --base-path $fixture --system $system
)
assert equal ($resolved_publication.entrypoint | path basename) main.nu
assert error {
  nix publication inspect module escaped --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert error {
  nix publication inspect application empty --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert equal (
  nix publication check --flake $fixture --base-path $fixture --system $system --realise
  | select role name status
) [{role: module, name: example, status: ok}]
assert equal (
  nix publication check --flake $malformed_fixture --base-path $malformed_fixture --system $system
  | select role name status
) [
  {role: module, name: escaped, status: error}
  {role: application, name: empty, status: error}
]

assert equal ($tasks | get name | sort) [
  after-failure
  build
  cycle-a
  cycle-b
  failing-build
  inline
  inline-failure
  main
  prepare
  realise
]
assert equal ($tasks | where name == main | get deps.0) [prepare realise]
assert equal ($selected.description | nix collect) "Run the requested task"
assert equal (
  nix task run main --flake $fixture --base-path $fixture --system $system --dry-run
) [
  {name: prepare, action: nushell}
  {name: realise, action: realise}
  {name: main, action: nushell}
]
assert error {
  nix task run cycle-a --flake $fixture --base-path $fixture --system $system --dry-run
}

let realised = (nix task run realise --flake $fixture --base-path $fixture --system $system | first)
assert equal $realised.task realise
assert equal $realised.action realise
assert equal $realised.outputs.0.target output
assert equal (($realised.outputs.0.physicalPaths.0 | path basename) | str ends-with "-nu-nix-task-output") true
assert error {
  nix task run realise unexpected --flake $fixture --base-path $fixture --system $system
}
if not $skip_nested_builds {
  let built = (nix task run build --flake $fixture --base-path $fixture --system $system | first)
  assert equal (open --raw $built.outputs.0.physicalPaths.0) built
  assert error {
    nix task run failing-build --flake $fixture --base-path $fixture --system $system
  }
  let failure_report = (
    nix task run after-failure --flake $fixture --base-path $fixture --system $system --report-errors
  )
  assert equal ($failure_report | select task status) [
    {task: failing-build, status: failed}
    {task: after-failure, status: skipped}
  ]
  assert equal ($failure_report.0.error | str contains "target `broken` failed") true
}
assert error {
  nix task run missing --flake $fixture --base-path $fixture --system $system --dry-run
}
assert error {
  nix task run old-version --flake $malformed_fixture --base-path $malformed_fixture --system $system --dry-run
}
assert error {
  nix task run main --flake $fixture --base-path $fixture --system $foreign_system
}
assert error {
  nix task run bad-path --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert error {
  nix task run bad-script-path --flake $malformed_fixture --base-path $malformed_fixture --system $system
}

let malformed_log = $"/tmp/nu-nix-malformed-(random uuid).log"
$env.NU_NIX_MALFORMED_LOG = $malformed_log
assert error {
  nix task run malformed --flake $malformed_fixture --base-path $malformed_fixture --system $system
}
assert equal ($malformed_log | path exists) false

let log = $"/tmp/nu-nix-task-(random uuid).log"
$env.NU_NIX_TASK_TEST_LOG = $log
$env.NU_NIX_TASK_ARGUMENT = "value"
let report = (nix task run main --flake $fixture --base-path $fixture --system $system value)
assert equal ($report | select task action) [
  {task: prepare, action: nushell}
  {task: realise, action: realise}
  {task: main, action: nushell}
]
assert equal $report.0.outputs []
assert equal $report.2.outputs []
$env.LAST_EXIT_CODE = 99
let inline_report = (
  nix task run inline --flake $fixture --base-path $fixture --system $system argument
)
assert equal ($inline_report | select task action) [{task: inline, action: nushell}]
let inline_failure = try {
  nix task run inline-failure --flake $fixture --base-path $fixture --system $system
  null
} catch {|error| $error }
assert equal $inline_failure.msg "task `inline-failure` failed with exit code 23"

assert equal (open $log | lines) [prepare "main:value:value" "inline:argument"]
rm $log

print "native flake task runner passed"
