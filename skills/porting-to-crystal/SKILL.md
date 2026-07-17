---
name: porting-to-crystal
description: Port behavior from Go, Rust, and similar upstreams into Crystal while preserving semantics, tests, and fixtures. Use when upstream behavior is the contract and Crystal implementation work is the main task.
---

# Porting To Crystal

Use this as the default implementation loop for behavior-faithful Crystal
ports.

## Route first

- Missing repo baseline or source checkout:
  `initialize-crystal-porting-project`
- Need parity manifests or drift checks:
  `cross-language-crystal-parity`
- Need dependency selection:
  `find-crystal-shards`
- Need to patch installed shard code under `lib/`:
  `crystal-shard-lib-patch`
- Need Bubble Tea example parity:
  `bubbletea-port-example-parity` and `bubbletea-parity-workflow`

## Core rule

Upstream behavior is the source of truth. Port behavior first, then express it
with Crystal idioms only where semantics stay unchanged.

## Preflight

Before implementation:

1. Confirm the source-of-truth checkout exists and is pinned.
2. Confirm repo scaffolding is in place.
3. Confirm parity planning exists under `plans/inventory/`.
4. If upstream location is still ambiguous, stop and resolve it first.

## Porting loop

### 1. Lock the source of truth

- Record the exact upstream revision.
- Treat upstream tests and fixtures as normative.
- Read the relevant source module and the nearest upstream tests before editing.

### 1.5 Use DeepWiki for vendor logic lookup

When the vendor code is large, subtle, or unfamiliar, ask DeepWiki about the
actual upstream repository that owns the source under `vendor/`.

- Use the real vendor repo identity such as `{owner}/{repo}`, not this Crystal
  port repo, when you ask for logic explanations.
- Ask for the behavior and invariants of the exact upstream module, type, or
  function you are porting, plus the nearest upstream tests when relevant.
- Use DeepWiki to accelerate reading and to surface relationships you may miss,
  but do not treat it as a substitute for reading the vendor source and tests.
- After using DeepWiki, verify the answer against the checked-in vendor files
  before changing Crystal code or updating parity status.

### 2. Work from the parity inventory

Use `cross-language-crystal-parity` to keep `plans/parity.md` and
`plans/inventory/*` current. Do not treat parity tracking as optional notes.

When the repo has a generated parity bundle, use it with the right priority:

- `parity.tsv`, `completion_status.tsv`, and `completion_incomplete.tsv` are
  the main signals for what is still missing, drifting, or untested.
- `rank.tsv`, `safe.tsv`, `slices.tsv`, `seed.md`, and `track.tsv` are
  secondary planning heuristics for centrality and batching.
- Helper, closure, and inlined-local-function rows are useful for discovering
  renamed or absorbed behavior, but they should not become the default unit of
  signoff if the user-visible feature is already represented elsewhere.

### 3. Translate behavior, not style

- Preserve parameter order, edge cases, and invalid-input behavior.
- Use explicit numeric widths when signedness or range matters.
- Use `Bytes` for binary semantics instead of `String`.
- Preserve data-structure and boundary semantics when behavior depends on them.

### 4. Port tests early

- Port upstream tests as first-class work.
- If upstream lacks tests, write characterization specs from observable
  behavior and mark inferred behavior clearly.
- Do not weaken assertions or change fixtures just to fit the current Crystal
  implementation.
- Prefer testing the user-visible behavior or exported unit when upstream local
  helpers were inlined, converted to closures, or absorbed into a larger
  Crystal method.

### 5. Use small red-green cycles

For each feature:

1. port the next missing or failing upstream-parity spec
2. make the smallest change that turns it green
3. run focused checks
4. repeat until the whole feature is done

Do not stop at helper-sized progress while the top-level feature is still open.
Use helper-level parity rows as breadcrumbs, not as the default finish line.

### 6. Verify continuously

Run focused checks during implementation, then the full repo gates before
closing the feature:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

For inventory drift and adversarial verification, use the canonical scripts from
`cross-language-crystal-parity`.

When the repo supports it, also keep the completion flow reproducible:

- prefer invoking the bundled parity scripts from the installed
  `cross-language-crystal-parity` skill directory so the workflow stays on the
  current skill version
- copy or refresh repo-local wrappers only when you intentionally want the repo
  to own and maintain its own parity script fork
- verify that in-memory completion evaluation and written
  `completion_status.tsv` / `completion_incomplete.tsv` artifacts agree

## Completion

A feature is complete only when all are true:

1. the API surface is implemented
2. relevant upstream tests or equivalent characterization specs exist
3. Crystal gates pass
4. fixtures or output-sensitive behavior match upstream expectations
5. parity inventory and plan entries are updated
6. any intentional divergence is documented

Internal helper rows that only document inlining or closure conversion should
not outweigh a green top-level feature unless the behavior they carry is still
unverified.

## Common failure modes

- changing behavior in the name of being more idiomatic
- picking the wrong numeric width or signedness
- using `String` for binary data
- porting implementation without parity tests
- forgetting to cite the upstream revision used

## Extra references

- `references/rust-porting.md`
- `references/completion-gate.md`
- `references/crystal-collection-design.md`
