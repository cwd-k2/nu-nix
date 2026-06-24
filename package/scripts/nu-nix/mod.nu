# nu-nix — Nix integration for Nushell.
#
# Provides two kinds of commands:
#
#   nu-nix <subcommand>  — structured Nix commands returning Nu tables/records
#                          (develop, shell, build, search, flake show, …)
#
#   from nix / to nix   — pipeline primitives for Nix ↔ Nu value conversion
#
# Setup (NixOS, via the nu-nix module):
#
#   programs.nu-nix.enable = true;
#   programs.nu-nix.autoLoad = true;
#
# After rebuilding, open a new Nushell session and run:
#
#   use nu-nix *
#
# Manual use (development):
#
#   use /path/to/package/scripts/nu-nix/mod.nu *

export use commands.nu *
export use from-nix.nu *
export use to-nix.nu *
