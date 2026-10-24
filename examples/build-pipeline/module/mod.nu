export def make-report [project: string, items: list<any>, version: string] {
  let enabled = ($items | where enabled)
  {
    project: $project
    version: $version
    item_count: ($items | length)
    enabled_count: ($enabled | length)
    enabled: ($enabled | select name owner)
  }
}
