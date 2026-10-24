# Integrated project example

This is the reference consumer project. It shows one set of artifacts across
their authoring, discovery, execution, and installation surfaces; it does not
define a second Nushell package ecosystem.

## What is defined where

| File or output | Role |
| --- | --- |
| `default.nix` | Builds the generated modules, application, composed session, and tasks. |
| `app/` | Multi-file Nushell application packaged by `mkNuApplication`. |
| `tasks/` | Explicit development effects; cacheable inputs remain Nix derivations. |
| `nushell.<system>` | Publication metadata for the module, plugin, application, and callable export. |
| `packages.default` / `apps.default` | Standard Nix distribution and execution of the application. |
| `packages.session` / `apps.session` | Standard Nix distribution and execution of the composed Nushell. |

The same application derivation appears in `packages.default`, `apps.default`,
the `greeter` publication, and a task runtime. These are views for different
consumers, not copies or different package formats.

`contextModule` renders Nix data as importable Nushell constants.
`environmentModule` supplies environment values to the packaged application.
The application uses both modules plus `hello`. The session then composes the
published `context` module, native `nix` plugin, `greeter` application, and the
ordinary `jq` package.

## Use the normal application

No composed session is needed to run a packaged application:

```nushell
nix run ./examples/integrated-project -- Ada | from json
```

The application carries its own runtime modules and environment. This is the
right shape for a command users invoke, as opposed to commands they want
available while exploring interactively.

## Explore in a fresh session

```nushell
nix run ./examples/integrated-project#session
# The following commands run inside the child Nushell.
use context *
$host
$features
greeter Ada | from json
nix eval '40 + 2' | nix collect
which jq
exit
```

The module is importable as `context`, plugin commands are registered, the
application is on `PATH` as `greeter`, and `jq` is also on `PATH`. `use context
*` remains explicit: the session makes the module resolvable but does not
silently import its names. Exiting returns to the unchanged parent shell.

That fresh process is intentional. Nushell resolves modules and plugin
signatures at parse time, so selecting components is a session boundary rather
than a runtime package mutation.

## Keep the session

For one user, install the package through the normal Nix profile:

```nushell
nix profile add ./examples/integrated-project#session
nu-nix-integrated-session
nix profile list
```

For a declarative installation, expose this project as a flake input and put
`inputs.project.packages.${system}.session` in `environment.systemPackages` or
`home.packages`. The complete module fragments are in
[`../nixos.nix`](../nixos.nix) and
[`../home-manager.nix`](../home-manager.nix). Those mechanisms install the same
launcher; they do not recreate its module/plugin/application composition.

## Inspect and develop the interface

The following commands require nu-nix in the parent shell, normally through
NixOS or Home Manager autoloading:

```nushell
nix publication list --flake ./examples/integrated-project
nix publication inspect module context --flake ./examples/integrated-project
nix publication check --flake ./examples/integrated-project --realise
nix export call describe --flake ./examples/integrated-project --arguments [Ada]
nix task list --flake ./examples/integrated-project
nix task run show --flake ./examples/integrated-project
```

Publication metadata answers “what role and entrypoint does this package
provide?” It does not load or install the package. The export is a callable Nix
function. Tasks describe effects: `runtime -> prepare -> check -> show`
realises cacheable inputs, writes `.nu-nix-example/report.json`, validates it,
and displays it.

The local `path:../..` input makes this example test the repository checkout.
In an independent project, replace it with the released nu-nix flake URL and
commit the resulting `flake.lock`.
