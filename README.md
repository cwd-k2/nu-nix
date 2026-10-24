# nu-nix

Native Nix values and Nix-backed project workflows for Nushell.

nu-nix evaluates Nix expressions and flakes through the public Nix C APIs.
Results remain lazy `NixValue`s while Nushell traverses them, without a
`nix eval` subprocess or JSON value boundary.

This is an experimental project. Commands, flake outputs, builders, package
composition, and schemas may change without compatibility aliases or migration
support. Only the Nix and Nushell revisions pinned by this flake are supported.

## User model

| Concept | Purpose | Commands |
| --- | --- | --- |
| Value | inspect and transform lazy Nix values | `nix eval`, `nix flake outputs`, `nix call`, `nix collect`, `nix realise` |
| Export | call Nix functions published by a flake | `nix export list`, `inspect`, `call` |
| Task | plan and run named project effects | `nix task list`, `nix task run` |
| Workflow | use Nix-owned build, profile, and environment operations as Nu data | `nix build`, `develop`, `search`, `profile ...` |

`nix` is the normal entry point. Exact commands integrated by nu-nix return
native or structured Nu data; other commands fall through to the external Nix
CLI. Use `^nix` when a script must require raw CLI behavior even if nu-nix adds
an integrated command later. The conceptual model and exact boundaries are in
[Integration model and status](docs/integration-status.md).

## Install

### NixOS

```nix
{
  inputs.nu-nix.url = "github:cwd-k2/nu-nix";

  outputs = { nixpkgs, nu-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nu-nix.nixosModules.default
        ({ config, ... }: {
          programs.nu-nix = {
            enable = true;
            autoLoad = true;
          };

          # Optional login-shell compatibility launcher.
          users.users.alice.shell = config.programs.nu-nix.loginShellPackage;
        })
      ];
    };
  };
}
```

### Home Manager

```nix
{
  imports = [ inputs.nu-nix.homeManagerModules.default ];
  programs.nu-nix = {
    enable = true;
    autoLoad = true;
  };
}
```

For a package-only installation, load the packaged plugin registry and module:

```nushell
plugin use --plugin-config ~/.nix-profile/share/nushell/nu-nix/plugin.msgpackz nix
use ~/.nix-profile/share/nushell/nu-nix *
```

`packages.nu-nix-bash` is a separate, optional login-shell compatibility
package. Home Manager installations do not pull it in.

## Values

Evaluation returns a lazy native value:

```nushell
let value = (nix eval '{
  answer = 40 + 2;
  nested = { enabled = true; items = [ 1 2 3 ]; };
  unused = throw "still lazy";
}')

$value | nix attr names              # [answer nested unused]
$value.answer | nix collect          # 42
$value.nested.enabled | nix collect  # true
```

Nu values can become native Nix values, and Nix functions remain callable:

```nushell
let select = (nix eval 'name: values: values.${name}')
$select | nix call answer {answer: 42} | nix collect

let native = ({enabled: true, items: [1 2 3]} | into nix)
$native.items.1 | nix collect
```

`nix collect` explicitly forces and converts a selected subtree. `nix realise`
realises the store references retained by a contextual Nix string. See
[native-values.nu](examples/native-values.nu) and
[native-functions.nu](examples/native-functions.nu).

## Flake interface

flake-parts consumers can import `flakeModules.default` and publish a
versioned `nushell.<system>` interface:

```nix
{
  imports = [ inputs.nu-nix.flakeModules.default ];

  perSystem = { pkgs, ... }: {
    nushell.modules.example = {
      package = exampleModule;
      entrypoint = "share/nushell/example/mod.nu";
      description = "Example module";
    };

    nushell.exports.select = inputs.nu-nix.lib.mkNuExport {
      inherit pkgs;
      arguments = [ "name" "values" ];
      result = "lazy";
      function = name: values: values.${name};
    };
  };
}
```

Modules, plugins, and applications remain ordinary Nix packages. The
`nushell.<system>` entries add author-facing role and entrypoint metadata for
validation and diagnostics; they are not another installable format. Exports
are callable Nix functions with explicit result forcing policy.

There are two representations at this boundary. In flake-parts configuration,
authors provide a component specification whose `package` is a derivation.
The module publishes a wire descriptor whose `package` is a contextual Nix
string that the native runtime can realise directly. A flake which writes the
`nushell.<system>` output by hand must use that wire form:

```nix
{
  type = "nu-nix-publication";
  version = 1;
  role = "module";
  package = "${exampleModule}";
  entrypoint = "share/nushell/example/mod.nu";
  description = "Example module";
}
```

Published entrypoints are always non-empty package-relative paths. Local
component specifications passed to `mkNuSession` may use either derivations or
already-published contextual strings; the resulting session is still an
ordinary package.

```nushell
nix publication list
nix publication inspect module example
nix publication resolve module example
nix publication check --realise
nix export list
nix export call select --arguments [answer {answer: 42}]
```

The `nix publication` commands inspect this metadata. They are mainly
an author and diagnostic surface, not a prerequisite for using a packaged
module, plugin, or application. `resolve` does not dynamically load anything:
Nushell resolves `use` and plugin signatures at parse time.

## Fresh-session composition

`lib.mkNuSession` composes published or local module, plugin, and application
descriptors into an ordinary Nix package which launches a fresh Nushell
process. Declared modules are importable by name, plugin executables are loaded
by the new process, applications are exposed on `PATH` by name, and ordinary
Nix packages can be added to the same `PATH`.

```nix
nuSession = inputs.nu-nix.lib.mkNuSession {
  inherit pkgs;
  name = "project-nu";
  inherit (published) modules applications plugins;
  packages = [ pkgs.jq ];
};
```

The session launcher is a normal derivation. It can be built, exposed as a
flake package or app, and installed through normal Nix mechanisms. Starting it
creates the parse boundary required for its modules and plugins; it does not
inject them into an already running Nushell process.

Install it like any other package; the nu-nix modules do not maintain a second
composition or installation schema:

```nix
# NixOS
environment.systemPackages = [ nuSession ];

# Home Manager
home.packages = [ nuSession ];
```

This does not autoload every component into ordinary Nushell sessions. It puts
the named `project-nu` launcher on `PATH`; invoking it starts the composed fresh
session.

## Tasks

Tasks are explicit effects published under `tasks.<system>`. With the
flake-parts module they are declared and type-checked per system:

```nix
perSystem = { pkgs, ... }: {
  tasks.check = inputs.nu-nix.lib.mkNuTask {
    inherit pkgs;
    description = "Run project checks";
    runtimeInputs = [ pkgs.cargo ];
    script = ./tasks/check.nu;
  };
};
```

```nushell
nix task list
nix task run check --dry-run
nix task run check
nix task run check --report-errors
```

Cacheable work belongs in derivations. `mkDerivationTask` exposes named
derivation targets; `mkNuTask` handles orchestration and development effects.
Dependencies order effects and never turn stdout into implicit dataflow. The
full contract is in [Task model](docs/task-model.md), with a runnable example in
[examples/integrated-project](examples/integrated-project).

## Nix workflows

Operations whose semantics belong to the Nix CLI cross an explicit structured
process boundary:

```nushell
nix build .#default
nix search nixpkgs jq
nix path-info /nix/store/...
nix profile list
nix profile add .#tool
nix profile upgrade tool
nix profile remove tool
nix profile history
nix profile rollback
nix develop .#default
nix activate .#default
nix deactivate
```

`nix activate` projects exported variables and PATH into the current Nushell
session. It does not run Bash functions or `shellHook`; use `nix develop` when
the complete development-shell behavior is required.

Profile mutations retain the Nix CLI's transaction semantics and then return
the resulting profile as a Nu table. `nix profile history` remains text because
Nix does not expose a machine-readable history format. Installing a composed
session changes the profile generation; its modules and plugins become active
when that launcher starts a new Nushell process, not in the shell which ran the
profile command.

Commands without an integrated definition retain raw CLI behavior:

```nushell
nix store gc       # falls through to the external CLI
^nix build .#tool  # explicitly require raw build output
```

Nushell selects an exact integrated subcommand while parsing. Constructing the
subcommand dynamically, such as `nix ...$arguments`, selects the catch-all
`nix` command and therefore preserves raw CLI behavior even when the arguments
begin with `build` or `profile`. Scripts that require structured output must
spell the integrated command explicitly and branch before invoking it.

## Nix library

- `lib.mkNuModule`: package a Nushell module tree.
- `lib.mkNuApplication`: package a multi-file Nushell command.
- `lib.mkNuSession`: compose modules, plugins, applications, and packages
  for a fresh Nushell process.
- `lib.mkNuModuleFromValue`: render Nix data into a typed Nushell module.
- `lib.mkNuEnvModule`: generate an `export-env` module.
- `lib.runNuCommand`: run Nushell as a Nix build action.
- `lib.mkNuTask`: declare an effectful Nushell task.
- `lib.mkDerivationTask`: declare named cacheable targets.
- `lib.mkNuExport`: publish a callable Nix function.

The two descriptor-only builders, `mkDerivationTask` and `mkNuExport`, accept
either `pkgs` for API consistency or `lib = pkgs.lib` when a full package set is
not otherwise needed.

The [integrated project example](examples/integrated-project) combines these
builders with the flake interface and task model:

```nushell
nix publication list --flake ./examples/integrated-project
nix export call describe --flake ./examples/integrated-project --arguments [Ada]
nix task run check --flake ./examples/integrated-project
nix run ./examples/integrated-project -- Ada
```

The [examples guide](examples/README.md) starts from the user's actual
interactive choices: use nu-nix in an ordinary shell, try a disposable project
session, or install the same session launcher through a profile, NixOS, or Home
Manager. It also explains which files and outputs own each part of the example.

The [build pipeline example](examples/build-pipeline) exercises the reverse
direction: Nushell runs inside a pure Nix build, while tasks publish and check
its immutable result as an explicit local effect.

## Development and design

```nushell
nix develop
nix fmt .
nix flake check --print-build-logs

# Requires a real Nix daemon; keep it outside `nix flake check`.
let work = (mktemp -d)
nu --no-config-file tests/consumer/profile-lifecycle.nu (pwd) ($work | path join run)
```

Nix and Nushell revisions are an implementation contract for the native plugin.
When updating `flake.lock`, run the full check above, then evaluate every declared
system and re-run Rust linting:

```nushell
nix flake check --all-systems --no-build
^nix develop --command cargo clippy --manifest-path crates/nu-plugin-nix/Cargo.toml --all-targets -- -D warnings
^nix develop --command cargo fmt --manifest-path crates/nu-plugin-nix/Cargo.toml --all -- --check
```

- [Integration model and current status](docs/integration-status.md)
- [Architecture and ownership](docs/architecture.md)
- [Task model](docs/task-model.md)
- [Active roadmap](docs/roadmap.md)
- [Runnable examples](examples/README.md)
