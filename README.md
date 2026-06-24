# nu-nix

Small helpers for using Nushell with Nix and NixOS-WSL.

`nu-nix` provides two binaries:

- **`nu-bash`** — login-shell compatibility wrapper. Delegates `-c`/`-lc` and
  other argument-based invocations to Bash (needed by tools like Zed, ssh, and
  WSL launchers), while starting Nushell for human interactive terminals.
- **`nu-nix`** — subcommand dispatcher that bridges Nix and Nushell: some
  subcommands replace Bash with Nushell as the interactive shell, others parse
  Nix JSON output into Nushell tables. Unknown subcommands fall through to the
  underlying `nix` CLI or a `nix-*` binary.

## Commands

```
nu-nix --help
```

### Nushell entry points

Enter a shell environment with Nushell instead of Bash:

```sh
nu-nix develop               # nix develop → nu
nu-nix develop .#default     # with explicit flake output
nu-nix shell nixpkgs#jq      # nix shell → nu
nu-nix nix-shell -p jq       # legacy nix-shell → nu
```

### Structured output (JSON → nu table)

Parse Nix JSON output directly into Nushell tables:

```sh
nu-nix build                          # nix build --json → table of output paths
nu-nix search nixpkgs jq              # nix search --json → package table
nu-nix path-info /nix/store/…        # nix path-info --json → store path details
nu-nix print-dev-env                  # nix print-dev-env --json → env var table
nu-nix why-depends /nix/store/… /…   # nix why-depends --json → dependency chain
nu-nix flake show                     # nix flake show --json → output table
nu-nix flake metadata                 # nix flake metadata --json → flake info
nu-nix derivation show                # nix derivation show → drv details
nu-nix profile list                   # nix profile list --json → installed pkgs
```

### Legacy nix-* wrappers

```sh
nu-nix nix-build -A hello            # nix-build → list of store paths
```

### Fallback

Any subcommand not listed above is passed through automatically:

```sh
nu-nix nix-env -q                    # → exec nix-env -q
nu-nix nix-store -q --references …  # → exec nix-store -q --references …
nu-nix log /nix/store/…             # → exec nix log …
nu-nix copy …                        # → exec nix copy …
```

Subcommands starting with `nix-` are dispatched to the corresponding `nix-*`
binary; all others are forwarded to `nix <subcommand>`.

## NixOS Module

With flakes:

```nix
{
  inputs.nu-nix.url = "github:cwd-k2/nu-nix";

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

The module registers `nu-bash` as a recognised login shell and installs
`nu-nix` system-wide. To use `nu-bash` as your login shell, set it explicitly
in your configuration:

```nix
users.users.alice.shell = "${config.programs.nu-nix.package}/bin/nu-bash";
```

## Package-Only Install

This installs `nu-nix` and `nu-bash`, but it does not change your login shell:

```sh
nix profile install github:cwd-k2/nu-nix
```

For login-shell integration, prefer the NixOS module.
