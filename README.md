# nu-nix

Nushell and Nix integration for NixOS.

Provides two things:

- **`nu-bash`** — login-shell compatibility wrapper that starts Nushell for
  interactive terminals while delegating script/argument invocations to Bash.
  Needed by tools that call the login shell directly (Zed, ssh, WSL launchers,
  PAM, `nix develop`, …).

- **`nu-nix` Nushell module** — structured Nix commands and Nix ↔ Nu value
  converters, loaded with `use nu-nix *`.

## Setup (NixOS)

```nix
{
  inputs.nu-nix.url = "github:cwd-k2/nu-nix";

  outputs = { nixpkgs, nu-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nu-nix.nixosModules.default
        {
          # Install nu-bash and the nu-nix Nushell module.
          programs.nu-nix.enable = true;

          # Automatically load the module in every Nushell session via the
          # vendor autoload mechanism — no `use nu-nix *` needed.
          programs.nu-nix.autoLoad = true;

          # Make nu-bash the login shell for a user.
          users.users.alice.shell = "${config.programs.nu-nix.package}/bin/nu-bash";
        }
      ];
    };
  };
}
```

For a local checkout, see [`examples/nixos.nix`](examples/nixos.nix).

## Usage

With `autoLoad = true`, all commands are available automatically in
every Nushell session — no `use nu-nix *` needed.

Without `autoLoad`, load the module manually with the full store path:

```nushell
use /run/current-system/sw/share/nushell/nu-nix *
```

### Shell entry

Enter a Nix environment with Nushell as the interactive shell:

```nushell
nu-nix develop                  # nix develop → nushell
nu-nix develop .#default        # explicit flake output
nu-nix shell nixpkgs#jq         # nix shell → nushell
nu-nix-shell -p jq              # legacy nix-shell → nushell
```

Exiting the child Nushell returns to the current Nushell session.

### Legacy nix-* wrappers

Thin wrappers for the classic `nix-*` CLI tools, with minor Nu enhancements
where useful:

```nushell
nu-nix-build -A hello           # → list of output paths
nu-nix-env -iA nixpkgs.jq      # manage user environment
nu-nix-channel list             # → name/url table
nu-nix-channel --update         # pass-through
nu-nix-collect-garbage -d       # remove old generations + GC
nu-nix-instantiate --eval --expr '1 + 1'
nu-nix-store --query --references /nix/store/…
nu-nix-prefetch-url https://…   # → trimmed hash string
nu-nix-hash --type sha256 ./file
nu-nix-copy-closure --to user@host /nix/store/…
```

### Structured data commands

These return Nu tables and records — fully composable in pipelines:

```nushell
nu-nix build                            # → table of output paths
nu-nix search nixpkgs jq               # → package table
nu-nix path-info /nix/store/…          # → store path details
nu-nix print-dev-env                    # → env var table
nu-nix why-depends /nix/store/… /…     # → dependency chain
nu-nix flake show                       # → flake output table
nu-nix flake metadata                   # → flake info record
nu-nix derivation show                  # → derivation details table
nu-nix profile list                     # → installed packages table
```

Because these are module functions (not an external binary), their output
flows as Nu values through the pipeline:

```nushell
nu-nix search nixpkgs python | where version >= "3.11" | to nix
nu-nix profile list | select name | each { get storePaths } | flatten
nu-nix flake show | where type == "packages" and system == "x86_64-linux"
```

### Nix ↔ Nu value conversion

```nushell
# Evaluate a Nix expression and return a Nu value
"{ x = 1 + 1; }" | from nix            # => {x: 2}
from nix nixpkgs#hello.meta             # => {broken: false, …}
from nix --file ./config.nix

# Serialize a Nu value to Nix expression syntax
{enable: true, port: 8080} | to nix
nu-nix profile list | select name | to nix | save packages.nix
```

For detailed conversion examples, see [`examples/usage.nu`](examples/usage.nu).

## Package-only install

```sh
nix profile install github:cwd-k2/nu-nix
```

Then load the module manually in your Nushell config:

```nushell
# ~/.config/nushell/config.nu
use ~/.nix-profile/share/nushell/nu-nix *
```

For login-shell integration, prefer the NixOS module.
