# `from nix` — evaluate a Nix expression and return the result as a Nu value.
#
# Three usage forms:
#
#   Expression string from stdin:
#     "{ x = 1 + 1; }" | from nix            # => {x: 2}
#     "builtins.filter (x: x > 2) [1 2 3 4]" | from nix
#
#   Flake installable (resolved by Nix):
#     from nix nixpkgs#hello.meta             # => {broken: false, ...}
#
#   .nix file:
#     from nix --file ./config.nix
#
# Limitations:
#   • Expressions that return functions (e.g. "x: x + 1") cannot be serialised
#     to JSON and will cause a Nix evaluation error.
#   • Nix path values (/nix/store/..., ./foo.nix, <nixpkgs>) are represented
#     as strings in JSON output — the path type is lost on the Nu side.
#   • --expr mode does not support relative `import` inside the expression;
#     use --file for expressions that import other files.

use internal.nu run-nix-json
use completions.nu complete-nix-value

export def "from nix" [
  installable?: string@complete-nix-value  # flake installable, e.g. nixpkgs#hello.meta
  --file (-f): path     # evaluate a .nix file
]: [string -> any, nothing -> any] {
  let expression = $in
  let source_count = ([
    ($expression != null)
    ($installable != null)
    ($file != null)
  ] | where { $in } | length)
  if $source_count == 0 {
    error make { msg: "from nix requires an expression on input, an installable, or --file" }
  } else if $source_count > 1 {
    error make { msg: "from nix accepts exactly one of pipeline input, an installable, or --file" }
  } else if $file != null {
    run-nix-json eval --file ($file | into string) --json
  } else if $installable != null {
    run-nix-json eval $installable --json
  } else {
    run-nix-json eval --expr ($expression | into string) --json
  }
}
