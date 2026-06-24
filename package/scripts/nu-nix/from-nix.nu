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

export def "from nix" [
  installable?: string  # flake installable, e.g. nixpkgs#hello.meta
  --file (-f): path     # evaluate a .nix file
]: [string -> any, nothing -> any] {
  if $file != null {
    ^nix eval --file ($file | into string) --json | from json
  } else if $installable != null {
    ^nix eval $installable --json | from json
  } else {
    ^nix eval --expr ($in | into string) --json | from json
  }
}
