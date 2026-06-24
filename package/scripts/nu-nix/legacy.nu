# Legacy nix-* wrappers — flat hyphenated commands.
#
# These wrap the old nix-* CLI tools (nix-shell, nix-build, …) that predate
# the unified `nix` command.  Prefer the `nu-nix` subcommands for new usage.

# Enter a legacy nix-shell running Nushell.
export def --wrapped "nu-nix-shell" [...rest: string] {
  exec "nix-shell" ...$rest "--run" $nu.current-exe
}

# Build using legacy nix-build; return output paths as a list.
export def --wrapped "nu-nix-build" [...rest: string] {
  ^nix-build ...$rest | lines
}
