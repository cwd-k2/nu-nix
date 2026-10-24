# Integration model and status

nu-nix joins Nix and Nushell where their semantics can be preserved. It does
not measure integration depth by eliminating every subprocess or by copying the
Nix CLI into Nushell.

The project is experimental. Names, schemas, and command shapes may change
without a compatibility layer while this model is being tested.

## User model

The public concepts are classified by what they represent, not by which
implementation executes them.

| Concept | Meaning | Main surface |
| --- | --- | --- |
| Value | a lazy Nix value being inspected or transformed | `nix eval`, `nix flake outputs`, `nix call`, `nix collect`, `nix realise` |
| Export | a documented Nix function published for Nushell callers | `nushell.<system>.exports`, `nix export ...` |
| Task | a named project effect with dependencies and an explicit runtime | `tasks.<system>`, `nix task ...` |
| Workflow | an operation owned by the Nix CLI, presented as structured Nu data | `nix build`, `nix develop`, `nix profile ...` |

These categories should not be collapsed:

- a value is lazy data, not an installable;
- an export computes a value and does not imply installation;
- a task performs an effect and is not a substitute for a derivation;
- a workflow retains the Nix CLI's installable and mutation semantics.

Module, plugin, and application are concrete Nushell delivery forms, not
another umbrella concept. Their entries under `nushell.<system>` are
publication metadata for authors and diagnostics. The referenced derivations
continue to appear in standard `packages`, `apps`, or configuration where
appropriate. Tasks remain in `tasks.<system>` so an effect is not mistaken for
a packaged component.

## What deep integration means

Integration is deep when crossing the boundary preserves the properties that
matter to the originating system:

1. **Type fidelity** — common values cross without JSON or source-string
   guessing.
2. **Laziness** — selecting one attribute does not force an unrelated value.
3. **Store context** — a Nix string keeps its build dependencies until an
   explicit realisation boundary.
4. **Function identity** — a Nix function remains callable instead of becoming
   printed text.
5. **Ownership and lifetime** — evaluator generations, value handles, and
   cancellation have explicit behavior.
6. **Effect honesty** — builds, profile mutation, task execution, and
   environment changes remain visible as effects.
7. **One package identity** — standard Nix outputs and Nushell metadata refer
   to the same derivation rather than creating a parallel package format.

Native execution is useful where it provides these properties. It is not a
goal by itself. A structured subprocess is the deeper integration when the Nix
CLI owns the operation's language and transactional behavior.

## What each side gains

Nushell gains from Nix:

- reproducible construction and distribution of modules, applications, and
  plugins;
- lazy evaluation and callable Nix functions inside structured pipelines;
- store identity and dependency context that survive until realisation;
- system-specific project interfaces and pinned tool runtimes.

Nix gains from Nushell as its user-facing environment:

- interactive inspection of lazy values using cell paths and tables;
- typed composition with ordinary Nu records and lists;
- readable structured results for builds, profiles, environments, and tasks;
- an explicit orchestration layer for development effects that do not belong
  in pure derivations.

This benefit is intentionally asymmetric at runtime: Nushell embeds access to
Nix values, while the Nix evaluator does not execute Nushell or gain Nushell
primops. Nix benefits through better consumption and operation of Nix-defined
projects, not by importing a second evaluator into the Nix language.

## Distribution model

Nix owns distribution. It fetches sources, selects versions, builds immutable
closures, provides binary caches, and installs or rolls back packages through
profiles and declarative configuration. nu-nix does not add a package index,
dependency solver, mutable component database, or install transaction.

The expected path is therefore: publish a normal derivation through a flake or
Nixpkgs, resolve and build it with Nix, persist it with a profile or declarative
configuration, then expose it through the Nushell mechanism appropriate to its
role. Explicit flake references and existing Nix package discovery remain the
distribution namespace.

Nushell owns how each delivered form becomes usable:

| Delivered form | Normal Nushell expectation | nu-nix/Nix projection |
| --- | --- | --- |
| module | files found through `NU_LIB_DIRS`, then explicitly imported with `use` or `overlay use` at parse time | install a module tree and add its directory to the search path of a fresh session |
| plugin | a version-compatible executable whose signatures are registered and available at parse time | package the executable with its matching Nushell version; use a packaged registry for the integration or `nu --plugins` for a composed session |
| application | an executable command found on `PATH` | install an ordinary Nix package or project it into a composed session's `PATH` |
| startup policy | config or vendor autoload loaded when Nushell starts | NixOS/Home Manager may install nu-nix autoload files; published components are not autoloaded merely because they exist |

These expectations follow Nushell's documented
[module search path](https://www.nushell.sh/book/modules/using_modules.html) and
[plugin lifecycle](https://www.nushell.sh/book/plugins.html).

This follows Nushell's distinct module, plugin, and executable mechanisms
instead of pretending they share one runtime installer. Availability and
import policy stay separate. Parser-visible changes normally take effect in a
new Nushell process; current-session activation is reserved for environment
variables and `PATH` that can actually change at runtime.

`mkNuSession` is an optional packaging helper for consumers who want those
forms pinned together behind one launcher. Its result is still an ordinary Nix
package. Declarative users put it in `environment.systemPackages` or
`home.packages`; imperative users may put it in a standard Nix profile. There
is no nu-nix-specific installed-session state.

The `nushell.<system>` descriptors solve publication-time discovery and
validation only. `nix publication` is the experimental author and diagnostic
interface to those descriptors; consumers do not need publication metadata to
run an application or session launcher.

## Current boundary

| Direction or operation | Supported | Boundary |
| --- | --- | --- |
| Nix to Nu values | lazy sets and lists, primitive collection, type inspection, contextual string realisation | native Nix C API |
| Nu to Nix values | null, booleans, signed integers, finite floats, strings, lists, records, and existing `NixValue`s | typed native construction |
| Nu to Nix source | the common data model plus explicit datetime, filesize, and duration coercions | `to nix` text serializer |
| Nix functions | curried application to typed Nu or native Nix arguments | `nix call` |
| Project interface | published module/application/plugin roles and callable exports | flake-parts `nushell.<system>` output |
| Fresh-session composition | named module imports, direct plugin loading, application commands, and ordinary packages | Nix derivation plus fresh Nushell process |
| Flakes | virtual/check locking and quoted attribute paths | native fetcher and flake APIs |
| Store | explicit store URI, contextual-string realisation, logical identities, and optional physical paths | native store API |
| Tasks | dependency planning, declared tool paths, and derivation target realisation | lazy values plus fresh Nu processes |
| CLI-owned workflows | installables, profile lifecycle, shells, development environments, and JSON inspection | structured external `nix` subprocesses |
| Other Nix commands | the external CLI's normal output and exit behavior | catch-all `nix`; `^nix` forces raw behavior |
| Environment activation | exported variables and PATH, with reversible nesting | `nix print-dev-env --json` |

## Depth assessment

The value plane meets the deep-integration criteria: it preserves types,
laziness, callable functions, string context, and evaluator ownership. The task
plane also has an honest effect boundary, although a task script necessarily
runs in a fresh Nushell process.

The project interface is useful and deliberately additive. A module, plugin,
or application declaration references a real Nix package and can be inspected.
Its published entrypoint is a non-empty validated relative path inside that
package. Standard `packages`, `apps`, and installation configuration
remain explicit projections of that package for different consumers. The
integrated example shows that the repeated reference is small and preserves
normal flake-parts merging. Automatically deriving those outputs would add
evaluation and override complexity without improving package identity, so it
is not part of the current model.

The authoring and runtime representations are intentionally distinct.
flake-parts accepts derivations in local component specifications and emits
contextual strings in the published wire descriptors. Raw flakes must write
the wire form explicitly. `mkNuSession` accepts either representation because
it needs only a package and entrypoint; it does not turn the descriptor into a
second package identity.

Two reference consumers now exercise both directions: Nix packaging a Nushell
application, and Nushell producing an immutable result inside a Nix build. They
do not expose enough repeated projection logic to justify a helper. The
flake-parts module provides the concrete project schema: `perSystem.nushell`
and `perSystem.tasks` are typed, validated during module evaluation, and
transposed to system-keyed outputs.

An additional out-of-tree consumer exercise composed module-only,
application-only, and plugin-only sessions. All three resolved through a fresh
session without an installer or mutable component database. The exercise also
confirmed that raw publication outputs need contextual package strings, which
is now documented as the wire boundary rather than hidden behind flake-parts
coercion.

Upstream Nix 2.34 has no extension mechanism for registering custom flake
outputs with `nix flake check`. It therefore still warns that `nushell` and
`tasks` are unknown even though the flake-parts schema has validated them.
Adding an unused `schemas` output would not change that behavior, so nu-nix
does not advertise one.

Callable exports preserve Nix functions and enforce arity and result policy.
Their argument names are documentation for positional application; nu-nix does
not claim to enforce a richer type schema that the runtime does not implement.
The flake-parts module and runtime both validate the export descriptor envelope;
the function's domain remains dynamically checked by Nix when it is called.

CLI-owned workflows are intentionally complete at the structured-process
boundary rather than partially reimplemented through unstable C++ internals.
Their stdout is captured for structured decoding while stderr remains visible
during long-running operations.

A black-box consumer test also exercises a composed session through a clean,
real Nix profile. It adds and inspects the package, starts the fresh session,
upgrades it, rolls back, removes it, and rolls back the removal. The launcher
tracks the selected profile generation throughout. This confirms that no
nu-nix-owned installation state or lifecycle command is needed. Profile
history remains diagnostic text: on Nix 2.34 an upgrade can change the store
path while its textual history diff says `No changes`, so state-sensitive code
uses `nix profile list --json` and the generation symlink instead.

The `nix` catch-all invokes the external CLI for commands without an exact
integrated definition. Exact integrated commands remain discoverable through
`nix commands`. `^nix` bypasses nu-nix command selection and is the stable
escape hatch for scripts that require raw output even if a command is
integrated later.

Exact command selection is a Nushell parse-time boundary. A call such as
`nix ...$arguments` resolves to the catch-all before the argument values are
known; it does not redispatch to `nix build` or another integrated subcommand
at runtime. Code that depends on an integrated output contract must use the
literal command name and put any dynamic choice outside that invocation.

The native bridge is more than a JSON adapter: values stay lazy, functions
remain callable, and Nix string context survives until an explicit realisation
boundary. Nix functions, derivations, and contextual strings remain opaque when
their semantics cannot be represented faithfully as ordinary Nu values.

Long native calls observe Nushell interruption at the worker boundary. The C
API has no evaluator stop hook, so nu-nix returns immediately, abandons the
result, and resets the evaluator after the in-flight call returns. Runtime
status reports this as `safe-abandon-and-reset`; native structured progress is
reported as unavailable rather than simulated.

`into nix` is the lossless typed bridge over the common data model. `to nix` is
a source serializer and additionally performs documented coercions for Nu
values that have no Nix type. Native callers should prefer `into nix`; callers
generating an expression should use `to nix`.

## Installation boundary

The package boundary is separate from the command boundary:

- `packages.nu-nix` contains the native plugin, registry, and Nu module.
- `packages.native-plugin` contains only the Rust plugin.
- `packages.nu-nix-bash` is an optional login-shell compatibility launcher.
- NixOS and Home Manager modules install and optionally autoload the
  integration package; only NixOS registers the optional login shell.

Resolving publication metadata does not load a module because Nushell resolves
imports at parse time. `nix publication resolve` returns a realised entrypoint;
startup import policy remains explicit configuration or a composed session.

The publication command interface remains an author and diagnostic surface.
`mkNuSession` consumes those descriptors, creates named module and
application projections, and wraps a fresh Nushell process which loads the
declared plugin executables and any ordinary Nix packages. The integrated
example exercises all four inputs. The result is installed through ordinary
Nix package lists or profiles.

The standard Nix profile is also the imperative persistence boundary.
Integrated add, upgrade, remove, and rollback commands perform the native Nix
transaction and return the resulting profile as structured data. History stays
textual because the Nix CLI exposes no machine-readable history format.

This is not a separate package manager. The independent consumer and real
profile exercises did not reproduce a question that requires additional
provenance or installed-state machinery; standard flake references, session
manifests, and profile JSON remain the corresponding sources of truth.
