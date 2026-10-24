# Build pipeline example

This project covers the opposite direction from `integrated-project`:
Nushell runs inside a pure Nix build to produce an immutable report. It keeps
the build artifact and working-tree effects visibly separate.

```text
Nix catalog ──> generated Nu module ──┐
                                      ├─> runNuCommand ─> report package
Nu report module ─────────────────────┘                        │
                                                             ▼
                                              build -> publish -> check
```

## What is defined where

| File or output | Role |
| --- | --- |
| `default.nix` | Defines catalog data, two modules, the report derivation, and tasks. |
| `module/mod.nu` | Reusable Nushell report logic packaged by `mkNuModule`. |
| `build/report.nu` | Pure build entrypoint run by `runNuCommand`. |
| `packages.default` | Immutable report in the Nix store. |
| `nushell.modules` | Author-facing metadata for the modules used by the build. |
| `tasks/` | Explicit publication and validation effects in the working tree. |

## Inspect the immutable result

With nu-nix loaded, `nix build` returns a table of output paths. Consume that
data directly instead of depending on a `result` symlink:

```nushell
let built = (nix build --no-link ./examples/build-pipeline)
open ($built.0.path | path join report.json)
nix publication check --flake ./examples/build-pipeline --realise
nix export call select-item --flake ./examples/build-pipeline --arguments [alpha]
```

If a script specifically needs the raw Nix CLI behavior, state that explicitly:

```nushell
^nix build ./examples/build-pipeline
open result/report.json
```

The first form is preferable in a Nu data pipeline. The second intentionally
uses raw CLI output and its filesystem link.

## Run the effectful pipeline

```nushell
nix task list --flake ./examples/build-pipeline
nix task run check --flake ./examples/build-pipeline
open .nu-nix-example/published-report.json
```

The `build` task only realises the store-backed report. `publish` is the sole
step that writes `.nu-nix-example/published-report.json`, and `check` validates
that local result. Task dependencies order those effects; stdout is not an
implicit data channel.

The local `path:../..` input is for testing this repository checkout. Replace
it with the released nu-nix flake URL in an independent project and commit the
lock file.
