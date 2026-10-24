# Roadmap

This document contains unresolved work only. Implemented behavior belongs in
the architecture and integration-status documents. New commands, state, and
schemas should be added only when a consumer journey demonstrates that the
existing Nix package, profile, publication metadata, or workflow surfaces are
insufficient.

## Stabilize the unified `nix` entry point

Audit consumer journeys for commands whose exact integrated form returns Nu
data while the catch-all form returns raw CLI output. Keep `nix commands`
authoritative, document `^nix` as the stable raw escape hatch, and treat adding
an integrated command as a user-visible output-contract change. Do not add
partial structured wrappers merely to increase command coverage.

Do not start with global package search. Explicit flake references and local
project interfaces are sufficient until independent publishing demonstrates a
need for an index.

## Stabilization and portability

- Exercise public command and builder shapes in additional projects before
  declaring a stable schema version.
- Consider a task sandbox only if concrete use requires it and the runner can
  enforce the advertised filesystem or network boundary. Do not publish
  advisory capabilities as security properties.
- Treat Nix or Nushell input updates as ABI/API migrations and run the pinned
  version checklist before merging.
- Add release notes and explicit migrations before replacing the experimental
  compatibility policy with a stable one.

## Upstream-dependent work

- Add native progress or forceful evaluator interruption if the public Nix C
  API exposes the required hooks.
- Register `nushell` and `tasks` as recognized custom flake outputs if upstream
  Nix provides a schema extension consumed by `nix flake check` and
  `nix flake show`.
- Consider persistent activation caches only with GC roots for every retained
  store reference.

The roadmap does not include a second dependency solver, a nu-nix-owned mutable
package database, a parallel package format, dynamic module loading into an
already parsed scope, automatic projection into unrelated flake outputs,
parallel task scheduling, or a general workflow DSL.
