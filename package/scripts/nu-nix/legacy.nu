# Legacy nix-* wrappers — flat hyphenated commands.
#
# These wrap the old nix-* CLI tools (nix-shell, nix-build, …) that predate
# the unified `nix` command.  Prefer the `nu-nix` subcommands for new usage.

# Enter a legacy nix-shell running Nushell.
export def --wrapped "nu-nix-shell" [...rest: string] {
  ^nix-shell ...$rest --run $nu.current-exe
}

# Build using legacy nix-build; return output paths as a list.
export def --wrapped "nu-nix-build" [...rest: string] {
  ^nix-build ...$rest | lines
}

# Manage the user environment with legacy nix-env.
export def --wrapped "nu-nix-env" [...rest: string] {
  ^nix-env ...$rest
}

# List subscribed channels as a name/url table.
export def "nu-nix-channel list" [] {
  ^nix-channel --list | lines | split column ' ' name url
}

# Manage channels with legacy nix-channel.
export def --wrapped "nu-nix-channel" [...rest: string] {
  ^nix-channel ...$rest
}

# Remove unreachable store paths.
export def --wrapped "nu-nix-collect-garbage" [...rest: string] {
  ^nix-collect-garbage ...$rest
}

# Instantiate a Nix expression (evaluate or create derivations).
export def --wrapped "nu-nix-instantiate" [...rest: string] {
  ^nix-instantiate ...$rest
}

# Low-level Nix store operations.
export def --wrapped "nu-nix-store" [...rest: string] {
  ^nix-store ...$rest
}

# Prefetch a URL into the store; return the hash string.
export def --wrapped "nu-nix-prefetch-url" [...rest: string] {
  ^nix-prefetch-url ...$rest | str trim
}

# Compute a Nix hash; return the hash string.
export def --wrapped "nu-nix-hash" [...rest: string] {
  ^nix-hash ...$rest | str trim
}

# Copy a store closure to/from a remote machine.
export def --wrapped "nu-nix-copy-closure" [...rest: string] {
  ^nix-copy-closure ...$rest
}
