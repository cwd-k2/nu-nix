use std/assert

let report = (open $env.NU_NIX_EXAMPLE_REPORT)
assert equal $report.generator "nu-nix"
assert equal ($report.items | length) 3
assert equal $report.application.greeting "hello task-run"
assert equal $report.application.host "example-host"
assert equal $report.application.configured "from-nix"
print "report is valid"
