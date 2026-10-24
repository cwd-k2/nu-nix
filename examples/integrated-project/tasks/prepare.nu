mkdir ($env.NU_NIX_EXAMPLE_REPORT | path dirname)

let report = {
  application: (^nu-nix-generated-example task-run | from json)
  generator: "nu-nix"
  jq: (^jq --version | str trim)
  items: [alpha beta gamma]
}

$report | to json --indent 2 | save --force $env.NU_NIX_EXAMPLE_REPORT
print $"generated ($env.NU_NIX_EXAMPLE_REPORT)"
