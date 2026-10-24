# Examples

These examples follow the boundaries a user actually encounters. They are not
a catalogue of every builder.

| Example | Question it answers | Primary audience |
| --- | --- | --- |
| `native-values.nu`, `native-functions.nu` | How do Nix values behave in a Nu pipeline? | interactive Nushell users |
| `integrated-project/` | How does a project package, publish, run, and install a Nushell experience? | project authors and users |
| `build-pipeline/` | How can Nushell produce a pure Nix build while tasks own local effects? | build and release authors |
| `nixos.nix`, `home-manager.nix` | How is the same project session installed declaratively? | NixOS and Home Manager users |

`integrated-project` is the central example. It produces one application and
one composed session, then exposes them through normal flake `packages` and
`apps`. NixOS, Home Manager, `nix profile`, and `nix run` all consume that same
session package; nu-nix does not add a separate installation system.

## Choose an interactive workflow

There are three useful session shapes. Choose based on how long the tools
should live, rather than trying to mutate the current Nushell process.

### 1. Use nu-nix in an ordinary Nushell

Enable `programs.nu-nix.autoLoad` through NixOS or Home Manager when the Nix
value and workflow commands should be available in every new Nushell. This is
the normal setup for commands such as:

```nushell
nix eval '{ answer = 40 + 2; }' | get answer | nix collect
nix build --no-link ./examples/build-pipeline
nix profile list
```

The two standalone scripts assume this setup:

```nushell
nu examples/native-values.nu
nu examples/native-functions.nu
```

### 2. Try a project's composed session

Use the flake app when the tools belong to one project and should disappear on
exit:

```nushell
nix run ./examples/integrated-project#session
# A fresh Nushell starts here.
use context *
$host
greeter Ada | from json
nix eval '40 + 2' | nix collect
exit
```

Modules and plugin signatures are resolved while Nushell parses a fresh
session. A running Nushell therefore cannot be retrofitted with a newly chosen
set of them. `mkNuSession` makes that boundary explicit and repeatable.

### 3. Keep the project launcher

Install the exact same session package in a user profile:

```nushell
nix profile add ./examples/integrated-project#session
nu-nix-integrated-session
nix profile list
```

Or install it declaratively with [`nixos.nix`](nixos.nix) or
[`home-manager.nix`](home-manager.nix). In every case the installed item is a
normal package containing the `nu-nix-integrated-session` launcher. Starting
that launcher opens the composed Nushell; it does not autoload the project's
components into unrelated shells.

## Work on a project

With nu-nix loaded in the ordinary shell, an author can inspect the declared
interface before running effects:

```nushell
nix publication list --flake ./examples/integrated-project
nix publication check --flake ./examples/integrated-project --realise
nix export call describe --flake ./examples/integrated-project --arguments [Ada]
nix task list --flake ./examples/integrated-project
nix task run check --flake ./examples/integrated-project
nix run ./examples/integrated-project -- Ada
```

`nix publication` describes roles and entrypoints for authors and diagnostics;
it is not an installer. `nix task` owns named project effects. Ordinary Nix
outputs remain the distribution surface.

The integrated `nix` commands return Nu data where a stable structured result
exists. Unknown subcommands fall through to the external CLI. Use `^nix` only
when the raw executable's exact text, flags, or future behavior is part of a
script's contract—for example, `^nix build` when deliberately relying on its
`result` symlink.
