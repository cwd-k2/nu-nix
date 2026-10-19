# nu-nix

Nushell and Nix integration.

Provides three things:

- **`nu-bash`** — login-shell compatibility wrapper that starts Nushell for
  interactive terminals while delegating script/argument invocations to Bash.
  Needed by tools that call the login shell directly (Zed, ssh, WSL launchers,
  PAM, `nix develop`, …).

- **`nu-nix` Nushell module** — structured Nix commands and Nix ↔ Nu value
  converters, loaded with `use nu-nix *`.

- **Nix builders** — `lib.mkNuModule` packages reusable Nushell modules, while
  `lib.mkNuApplication` builds multi-file applications with pinned modules,
  runtime commands, and environment.

## Setup (NixOS)

```nix
{
  inputs.nu-nix.url = "github:cwd-k2/nu-nix";

  outputs = { nixpkgs, nu-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nu-nix.nixosModules.default
        ({ config, ... }: {
          # Install nu-bash and the nu-nix Nushell module.
          programs.nu-nix.enable = true;

          # Automatically load the module in every Nushell session via the
          # vendor autoload mechanism — no `use nu-nix *` needed.
          programs.nu-nix.autoLoad = true;

          # Make nu-bash the login shell for a user.
          users.users.alice.shell = config.programs.nu-nix.package;
        })
      ];
    };
  };
}
```

For a local checkout, see [`examples/nixos.nix`](examples/nixos.nix).

## Setup (Home Manager)

```nix
{
  imports = [ inputs.nu-nix.homeManagerModules.default ];

  programs.nu-nix.enable = true;

  # Automatically load the module in every Nushell session for this user.
  programs.nu-nix.autoLoad = true;
}
```

The Home Manager module installs the package and, when `autoLoad` is enabled,
writes `nushell/autoload/nu-nix.nu` in the user's XDG config. It does not
register `nu-bash` as a login shell; use the NixOS module for that.

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

## Packaging Nushell applications

Package a module directory containing `mod.nu` and optionally expose it through
Nushell's vendor autoload convention:

```nix
packages.x86_64-linux.my-module = nu-nix.lib.mkNuModule {
  inherit pkgs;
  name = "my-module";
  src = ./my-module;
  autoLoad = true;
};
```

`lib.mkNuApplication` keeps a Nushell source tree intact, runs it without user
configuration, and makes the pinned `nu-nix` module available through the
application's module search path. Additional Nushell module packages must place
their modules under `share/nushell/`.

```nix
{
  packages.x86_64-linux.my-tool = nu-nix.lib.mkNuApplication {
    inherit pkgs;
    name = "my-tool";
    src = ./tool;
    entrypoint = "main.nu";
    runtimeInputs = [ pkgs.git ];
    nuLibraries = [
      nu-nix.packages.x86_64-linux.default
      another-nushell-module
    ];
    environment.MY_TOOL_MODE = "managed";
  };
}
```

The default `nuLibraries` already contains the matching `nu-nix` package, so it
can normally be omitted. `nuLibDirs` accepts additional module directories when
they are not packaged under `share/nushell/`. `extraWrapperArgs` provides an
escape hatch for `makeWrapper` options. Set `nuLibraries = [ ];` for an
application that does not import any Nushell modules; the wrapper then omits the
module search path entirely.

Nix values can also become exported Nushell constants without running Nushell
during Nix evaluation. Values may contain JSON-compatible scalars, lists, and
attribute sets; Nix paths become store paths.

```nix
packages.x86_64-linux.host-context = nu-nix.lib.mkNuModuleFromValue {
  inherit pkgs;
  name = "host-context";
  values = {
    host = "workstation";
    features = [ "audio" "graphics" ];
  };
};
```

Loading the resulting module with `use host-context *` exports `$host` and
`$features`. Export names must be valid Nushell identifiers.

`lib.mkNuEnvModule` produces a module with an `export-env` block. It can set
typed Nushell environment values and update list-valued path variables while
keeping the requested entries unique. Existing occurrences of those entries are
moved to the requested side; the order and duplicates of unrelated existing
entries are preserved. Set `autoLoad = true` to expose it through Nushell's
vendor autoload convention.

```nix
packages.x86_64-linux.session-env = nu-nix.lib.mkNuEnvModule {
  inherit pkgs;
  name = "session-env";
  autoLoad = true;
  variables.EDITOR = "nvim";
  prependPath.PATH = [ "/run/wrappers/bin" ];
};
```

`prependPath` and `appendPath` entries must be lists, and a variable cannot use
both operations. Existing values must also be lists, as Nushell's built-in
`PATH` value normally is.

The [generated application example](examples/generated-application) combines
all three builders: Nix declarations become a data module and an environment
module, then `mkNuApplication` makes both available to a multi-file Nushell
program. Run it directly from the example directory:

```sh
nix run . -- Ada
```

`lib.runNuCommand` runs a Nushell script as a Nix derivation builder. It gives
the script a clean Nushell session, makes declared Nushell libraries available,
and adds build tools to `PATH`.

```nix
checks.x86_64-linux.quality = nu-nix.lib.runNuCommand {
  inherit pkgs;
  name = "quality";
  script = ./scripts/check.nu;
  runtimeInputs = with pkgs; [ deadnix nixfmt-tree ];
  derivationArgs.src = ./.;
};
```

The default `nuLibraries` contains nu-nix. Use `nuLibraries = [ ];` for a
standalone script, `nuLibDirs` for unpackaged module directories, and
`derivationArgs` for values such as `src`, `meta`, or `passthru` that must
be passed to the underlying derivation.

## Package-only install

```sh
nix profile install github:cwd-k2/nu-nix
```

Then load the module manually in your Nushell config:

```nushell
# ~/.config/nushell/config.nu
use ~/.nix-profile/share/nushell/nu-nix *
```

For profile-level autoload, install the explicit autoload variant:

```sh
nix profile install github:cwd-k2/nu-nix#with-autoload
```

For login-shell integration, prefer the NixOS module.
