# nu-nix — Nix integration for Nushell.
#
# Provides one integrated `nix` command family plus data conversion:
#
#   nix <subcommand>     — integrated when available, otherwise the raw CLI
#   ^nix <subcommand>    — always invoke the external Nix executable
#
#   into nix             — convert ordinary Nu data to a live native Nix value
#   to nix               — serialize ordinary Nu data as a Nix expression
#
# Setup (NixOS, via the nu-nix module):
#
#   programs.nu-nix.enable   = true;   # install the plugin and this module
#   programs.nu-nix.autoLoad = true;   # vendor-autoload at startup (recommended)
#
# With autoLoad, the module is sourced automatically — nothing else needed.
#
# Without autoLoad, load the packaged registry and module manually:
#
#   plugin use --plugin-config /run/current-system/sw/share/nushell/nu-nix/plugin.msgpackz nix
#   use /run/current-system/sw/share/nushell/nu-nix *
#
# Development (without installing):
#
#   use /path/to/nu-nix/nushell/nu-nix/mod.nu *

export use cli.nu *
export use activation.nu *
export use inventory.nu *
export use to-nix.nu *
export use tasks.nu *
export use flake-interface.nu *
