use std/assert

let report = (open $env.NU_NIX_PIPELINE_PUBLISHED)
assert equal $report.project "build-pipeline"
assert equal $report.version "1"
assert equal $report.item_count 3
assert equal $report.enabled_count 2
assert equal $report.published true
print "published report is valid"
