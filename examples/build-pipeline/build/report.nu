use project-catalog *
use report-tools [make-report]

mkdir $env.out
make-report $project $items $env.REPORT_VERSION
| to json --indent 2
| save $"($env.out)/report.json"
