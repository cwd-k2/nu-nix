# nu-nix

Small helpers for using Nushell with Nix and NixOS-WSL.

`nu-nix` provides:

- `nu-bash`: a login-shell compatibility wrapper. It delegates `-c`/`-lc`
  and other argument-based invocations to Bash, while starting Nushell for
  human interactive terminals.
- `nu-nix`: explicit wrappers for starting Nushell after Nix has prepared an
  environment.

## Commands

```sh
nu-nix develop [nix develop args...]
nu-nix shell [nix shell args...]
nu-nix nix-shell [nix-shell args...]
```

Examples:

```sh
nu-nix develop
nu-nix develop .#default
nu-nix shell nixpkgs#jq
nu-nix nix-shell -p jq ripgrep
```

## NixOS Module

With flakes:

```nix
{
  inputs.nu-nix.url = "github:YOUR_USER/nu-nix";

  outputs = { nixpkgs, nu-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nu-nix.nixosModules.default
        {
          programs.nu-nix = {
            enable = true;
            loginShellUser = "nixos";
          };
        }
      ];
    };
  };
}
```

For a local checkout:

```nix
{
  imports = [
    /path/to/nu-nix/modules/nu-nix.nix
  ];

  programs.nu-nix = {
    enable = true;
    loginShellUser = "nixos";
  };
}
```

## Package-Only Install

This installs `nu-nix` and `nu-bash`, but it does not change your login shell:

```sh
nix profile install github:YOUR_USER/nu-nix
```

For login-shell integration, prefer the NixOS module.

## Why not an install script?

For NixOS, the cleaner practice is to expose a package and a NixOS module from
the flake, then import the module from your system configuration. A shell
installer that edits `/etc/nixos` would be less reproducible and harder to
review.
