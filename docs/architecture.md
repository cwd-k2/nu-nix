# Architecture

nu-nix has three explicit layers:

```text
Nushell session
  ├─ native commands ── nu_plugin_nix ── Nix C APIs
  ├─ task runner ────── lazy flake task values
  └─ effect commands ── nix CLI (builds and mutation only)
```

The implementation is intentionally tied to the Nix and Nushell revisions in
`flake.lock`. Keeping an ABI compatibility facade would obscure the design and
is outside this branch's scope.

The project API is experimental as well. Commands, builders, flake outputs,
package composition, and task schemas may change without a compatibility layer
or migration path. A schema version identifies accepted data; it does not
commit the runner to supporting previous versions.

## Native plugin

`crates/nu-plugin-nix` owns one lazily initialized evaluator runtime on a
dedicated worker thread. A bounded synchronous request channel serializes all
access, so the runtime's raw pointers never move between command threads. The
runtime initializes libutil, libstore, libexpr, fetcher, and flake settings and
opens the configured Nix store.

`nix eval` evaluates an expression in the native plugin process into an
arena-owned `nix_value`. Nushell receives a small `NixValue` custom value
containing an arena identifier. Attribute and list access is forwarded to the
plugin using lazy Nix C API accessors.

The important forcing boundaries are:

- `nix type` forces only the outer constructor.
- `nix attr names` forces the set spine but not attribute values.
- normal Nu cell-path access selects one child lazily.
- `nix collect` recursively forces and converts the selected subtree.
- `nix realise` realises the context of a selected Nix string.

Rendering an opaque `NixValue` produces a non-forcing summary. Deep conversion
only happens through `nix collect`, which applies depth and node limits so
cyclic or adversarial values fail without exhausting the plugin stack.

Arena entries carry a plugin session, evaluator generation, and slot. Nushell
notifies the plugin after the last engine-side copy of a value is dropped, at
which point its slot is reclaimed. `nix debug runtime reset` destroys the evaluator
and invalidates its generation; late drop notifications are harmless.

`into nix` constructs the unambiguous common data model—nulls, booleans,
signed integers, finite floats, UTF-8 strings, lists, and records—through typed
C API initializers. Existing `NixValue`s can be nested without forcing. Only a
top-level string passed with `--path` becomes a Nix path; nested strings remain
strings. Unsupported Nu values and invalid UTF-8 from Nix fail explicitly.
`nix call` applies a pipeline Nix function to typed Nu or native Nix arguments
without rendering source text.

## Flake evaluation

`nix flake outputs` parses a reference with the fetcher API, locks it in virtual
mode, and obtains the output attribute set from the flake API. It never writes a
lock file. A dot-separated fragment is traversed natively before the resulting
handle is returned.

Expression and flake evaluation therefore avoid both subprocesses and JSON.
Builds, profile changes, and development shell creation remain CLI operations
because their primary purpose is an external effect rather than value
transport.

`nix realise --details` returns the rendered value, logical store identities,
and any physical paths supplied by the configured store. The public C API does
not expose a portable full logical-path renderer, and remote stores need not
have a local physical path; commands that execute a result require one.

The evaluator lives in the persistent plugin process, not inside Nushell's own
address space. Effect commands use the external CLI intentionally, and
`nix activate` projects exported variables only; it does not execute Bash
functions or `shellHook`.

Lifecycle has three explicit scopes. `nix activate` changes reversible
environment state in the current parsed process. `nix develop`, `nix shell`,
and an `mkNuSession` launcher create a child Nushell, which provides the parse
boundary required by modules and plugins. Profiles, NixOS, and Home Manager
persist ordinary packages for later launcher invocations; nu-nix keeps no
parallel installed-state database.

Progress follows the same ownership boundary. External Nix operations stream
the CLI's stderr while reserving stdout for structured results. Native
evaluation exposes no synthetic percentage or event stream because the public
C API supplies neither a progress callback nor forceful evaluator
interruption. Runtime diagnostics report that limitation directly.

Pure traversal limits and handle identity are tested without loading Nix. The
resource layer also has a test destructor seam for malformed null returns and
cleanup-on-error; end-to-end checks continue to exercise the real C API.

## Builder runtime

`mkNuApplication` and `runNuCommand` make modules available through
`NU_LIB_DIRS` and load parser-visible plugins when the Nushell process starts.
Their default `nuLibraries` includes the nu-nix package, so the native `nix`
commands are loaded by default as well. Setting `nuLibraries = [ ]` also removes
that default plugin; callers can select executable plugin paths independently
through `plugins`.

`runNuCommand` executes as a pure Nix build action with a fresh writable `HOME`
under `TMPDIR`. This gives the embedded Nix runtime an isolated per-build state
directory without exposing or depending on a user home. Packaged applications
retain the caller's normal `HOME` because they execute outside the build action.

## Task model

Both task builders produce a versioned record under `tasks.<system>`:

```nix
{
  type = "nu-nix-task";
  version = 2;
  description = "...";
  deps = [ "other-task" ];
  action = {
    type = "nushell"; # or "realise"
    # action-specific fields
  };
}
```

File tasks capture and realise a source tree, so relative imports resolve from
a stable store directory. The default tree is the script's directory;
`sourceRoot` can explicitly widen it for parent-relative imports. Because the
tree enters the world-readable Nix store, it must not contain secrets. Inline
tasks are passed directly to a fresh Nushell process and do not create temporary
source files. Task stdout and stderr stream to the runner's stderr so the
structured execution report remains the only pipeline output.
Tool paths and environment values retain Nix string context and are realised
immediately before execution. By default PATH contains only `runtimeInputs`;
when there are none, `/dev/null` represents the otherwise unrepresentable empty OS
PATH. This controls command lookup but is not a sandbox: the child inherits the
caller's ambient environment and may access the filesystem and network.
Running a task trusts repository code.

`lib.mkDerivationTask` emits a `realise` action containing named contextual
derivation outputs. It shares dependency ordering with Nushell actions and
uses the native string-realisation primitive. See `docs/task-model.md` for the
schema and dependency contract.

The flake-parts module defines both `perSystem.nushell` and
`perSystem.tasks`. It validates the versioned task envelope during module
evaluation and transposes both interfaces into their system-keyed flake
outputs. Action-specific validation remains in the builders and task runner so
the module does not maintain a second execution schema.

`perSystem.nushell` is an authoring interface: component packages are ordinary
derivations. Transposition produces the published wire interface under
`nushell.<system>`, where each package is a contextual Nix string and each role
has a non-empty package-relative entrypoint. The native runtime consumes only
that wire form. `mkNuSession` operates on the common component fields and can
therefore compose either local derivations or published contextual strings.

## Nix packaging

The Nix layer is split by responsibility:

- `nix/lib`: public builders and validation.
- `nix/packages`: package composition.
- `nix/modules`: NixOS and Home Manager integration.
- `nushell/nu-nix`: commands loaded into a user's shell.

The integration package contains the plugin executable, an immutable plugin
registry, and the Nushell module. The optional `nu-nix-bash` login-shell launcher
is a separate package. Autoload activates the packaged registry and then
imports the module.

`mkNuSession` is a separate composition boundary. It consumes named component
specifications and ordinary packages, projects modules and applications
under their declared names, and wraps the pinned Nushell with the corresponding
include path, plugin executables, and `PATH`. Its output is an ordinary
derivation with a machine-readable component manifest. It is installed through
normal package lists or profiles; the nu-nix modules do not maintain a parallel
component database or installation schema.

## Safety boundary

Listing tasks never executes their scripts. Running a task is an explicit
effect equivalent to running repository code. Pure, cacheable work should be a
derivation or flake check; tasks should orchestrate those derivations or handle
development-only effects.
