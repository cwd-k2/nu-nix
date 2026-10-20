# Shared boundary for commands that consume Nix's machine-readable output.
export def --wrapped run-nix-json [...args: string]: nothing -> any {
  ^nix ...$args | from json
}
