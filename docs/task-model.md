# Task model

Tasks are versioned Nix data under `tasks.<system>`. The runner accepts one
common envelope and dispatches its action:

```nix
{
  type = "nu-nix-task";
  version = 2;
  description = "...";
  deps = [ "prerequisite" ];
  action = { /* discriminated action record */ };
}
```

Flakes using `flakeModules.default` declare these records as
`perSystem.tasks.<name>`. The module validates this envelope and transposes it
to `tasks.<system>.<name>`. Flakes not using flake-parts may publish the same
records directly.

`lib.mkNuTask` creates a `nushell` action. Its source, contextual environment,
and runtime `PATH` live under `action`. File sources are
captured in the Nix store; `sourceRoot` controls the captured tree. Captured
sources are world-readable and must not contain secrets.

`lib.mkDerivationTask` creates a `realise` action:

```nix
nu-nix.lib.mkDerivationTask {
  inherit pkgs;
  description = "Build cacheable prerequisites";
  targets = {
    package = pkgs.example;
    check = checks.example;
  };
}
```

Target names are labels within one task result. Target values are derivations
converted to contextual strings by Nix. Running the task sends each value to
the native `nix realise` command. On success, the runner returns an
execution-report table;
each row contains `task`, `action`, `status`, `outputs`, and
`error`; realised outputs contain `target`, `value`, `storePaths`, and
`physicalPaths`. Status is `succeeded`, `failed`, or `skipped`. `value` is the
rendered contextual string, `storePaths` contains portable hash/name
identities, and `physicalPaths` contains locally available paths. Context-free hand-authored
targets are rejected. Nushell action rows have an empty `outputs` list; script
stdout is routed to the runner's stderr so the data pipeline contains only the
report.
Multiple outputs should be named explicitly in `targets` by selecting the
desired output derivations.

## Dependency semantics

Dependencies are ordering and effect edges, not dataflow edges. The runner
performs a deterministic depth-first topological traversal, rejects missing
tasks and cycles, validates the complete plan before starting any action, and
executes each task at most once. `--dry-run` returns the validated task/action
plan. Only the requested root Nushell task receives command-line arguments;
realisation roots reject arguments.

A downstream script must declare required packages again in `runtimeInputs` or
its environment; it must not scrape a predecessor's stdout. Re-realisation is
cheap because the store caches derivations. This rule keeps task records simple
and makes cacheable data dependencies remain Nix dependencies.

## Execution and trust

Listing is evaluation only and never starts task actions. Running is an
explicit effect equivalent to running repository code. Foreign-system plans
may be inspected with `--dry-run`, but execution is rejected.

Structural validation completes before effects begin. By default a failed
action raises a Nushell error after execution stops. `--report-errors` instead
returns completed, failed, and unstarted rows; unstarted rows are marked
`skipped`. Realisation reports separate portable store identities from optional
physical paths. Executing a realised task script still requires local
physical-path lookup.

Nushell actions get a `runtimeInputs`-only `PATH`. When that list is empty, the
runner uses `[/dev/null]` because an empty OS PATH entry would search the current
directory. This controls external command lookup; it does not isolate the task.
The child inherits the caller's ambient environment and may access the
filesystem and network. Task code is trusted repository code. Derivation
actions execute through the Nix C API and do not
directly invoke the `nix` CLI. The store may still launch helpers from its Nix
configuration. Pure work belongs in derivations; Nushell actions are for
orchestration and development-side effects.
