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
#   programs.nu-nix.enable   = true;   # install nu-bash and this module
#   programs.nu-nix.autoLoad = true;   # vendor-autoload at startup (recommended)
#
# With autoLoad, the module is sourced automatically — nothing else needed.
#
# Without autoLoad, load manually with the full path:
#
#   use /run/current-system/sw/share/nushell/nu-nix *
#
# Development (without installing):
#
#   use /path/to/package/scripts/nu-nix/mod.nu *

export use commands.nu *
export use from-nix.nu *
export use to-nix.nu *
export use legacy.nu *
