---
name: porting-to-crystal
description: Execute behavior-faithful ports from Go, Rust, or similar languages into Crystal by translating APIs and tests while preserving upstream semantics and outputs. Use when implementing or continuing a source-based port where upstream behavior is the required contract.
---

# Porting to Crystal

## Purpose

Use this skill as the default implementation workflow for behavior-faithful
ports into Crystal.

Core rule: upstream behavior is the source of truth. Port behavior first, then
express it with Crystal idioms.

## Scope and Ownership

This skill defines the shared porting loop only. Use companion skills for
specialized workflows instead of duplicating those steps here.

Parity planning/check details are owned by
`cross-language-crystal-parity`, not by this skill.

| Need | Skill owner |
|---|---|
| New porting project setup, submodule/bootstrap, baseline docs | [initialize-crystal-porting-project](/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/SKILL.md) |
| Source API/test inventory, drift checks, backlog seeding (Go/Rust/Crystal/Java/Ruby) | [cross-language-crystal-parity](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/SKILL.md) |
| Crystal shard selection/replacement decisions | [find-crystal-shards](/Users/dominic/.agents/skills/crystal_forge/skills/find-crystal-shards/SKILL.md) |
| Local edits under `./lib` with upstream shard issue tracking | [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal-shard-lib-patch/SKILL.md) |
| Bubble Tea example parity and teatest/golden flow | [bubbletea-port-example-parity](/Users/dominic/.agents/skills/bubbletea-port-example-parity/SKILL.md) and [bubbletea-parity-workflow](/Users/dominic/.agents/skills/bubbletea-parity-workflow/SKILL.md) |

## Routing Matrix

Use this matrix to route work before implementation details:

| Trigger | Route to skill | Expected output |
|---|---|---|
| Repo missing baseline docs/meta setup | [initialize-crystal-porting-project](/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/SKILL.md) | Submodule + docs + quality-gate baseline |
| Need inventory/drift checks for Go/Rust/Crystal/Java/Ruby upstream | [cross-language-crystal-parity](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/SKILL.md) | `plans/inventory/*` manifests + drift results |
| Need shard selection/replacement decision | [find-crystal-shards](/Users/dominic/.agents/skills/crystal_forge/skills/find-crystal-shards/SKILL.md) | Ranked candidates + selected `shard.yml` entry |
| Need patch under `./lib` shard sources | [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal-shard-lib-patch/SKILL.md) | Local patch + upstream issue/traceability |
| Bubble Tea output parity work | [bubbletea-port-example-parity](/Users/dominic/.agents/skills/bubbletea-port-example-parity/SKILL.md) then [bubbletea-parity-workflow](/Users/dominic/.agents/skills/bubbletea-parity-workflow/SKILL.md) | Teatest/golden parity evidence |
| None of the above; direct behavior translation work | Stay in `porting-to-crystal` | Ported code + specs + gate results |

## Preflight

Before translation work:

```bash
ls -la CLAUDE.md AGENTS.md shard.yml 2>/dev/null
ls docs/ 2>/dev/null
git submodule status 2>/dev/null || true
```

If project scaffolding or source checkout is missing, run
`initialize-crystal-porting-project` first.

If no git submodule is configured, stop and ask source-of-truth location
questions before any port implementation:

1. "Should upstream be added as a git submodule?"
2. "Where is upstream source code located?"
   1. project root
   2. a subdirectory under this repo
   3. other path (explicit absolute/relative path)

Submodule definition for user clarity:

- a git submodule is a repo embedded in another repo at a pinned commit, used
  here to keep upstream source-of-truth reproducible.

## Inventory-First Rule

Porting work must be tracked in inventory manifests under `plans/inventory/`.
Do not treat parity tracking as optional project notes.

Required workflow:

1. Use `cross-language-crystal-parity` to bootstrap/validate the parity plan.
2. Implement against inventory items.
3. Update `<language>_port_inventory.tsv` statuses as work advances.
4. Use `cross-language-crystal-parity` checks/adversarial verification before
   marking work complete.

## Porting Loop

### 1) Lock source-of-truth

- Pin upstream via submodule or fixed commit.
- Record exact upstream revision in branch notes/PR text.
- Treat upstream tests and fixtures as normative behavior specs.

### 2) Build/refresh parity checklist

Track each unit being ported:

- public types/constants
- methods/functions and signatures
- error behavior
- tests and fixtures

If parity inventory is required, use `cross-language-crystal-parity` as the single
inventory workflow (supports Go, Rust, Crystal, Java, and Ruby).

### 3) Translate behavior, not style

- Keep parameter order, edge cases, and invalid-input outcomes identical.
- Prefer explicit numeric widths (`_u8`, `_i32`, etc.) where behavior depends
  on signedness/range.
- Use `Bytes` (`Slice(UInt8)`) for binary semantics; avoid `String` for raw
  byte payloads.
- Preserve boundary semantics exactly (for example half-open ranges).

### 4) Port tests as first-class work

- Port upstream tests into Crystal specs early.
- Keep fixtures/golden outputs equivalent.
- If upstream has no tests, create characterization specs from observable
  behavior and mark inferred behavior explicitly.
- Preserve upstream test logic exactly. Do not weaken assertions, skip
  branches, or rewrite expectations to fit the current implementation.
- Preserve upstream platform/environment gates exactly (OS/arch/feature
  checks). If a gate cannot run locally, mark it blocked with evidence rather
  than changing test behavior.

### 5) Verify continuously

Run quality gates frequently:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

For output-sensitive code, compare against upstream fixtures/goldens and fail
on diffs.

For inventory drift checks and adversarial verification, run the canonical
workflow from `cross-language-crystal-parity`.

## Language Mapping (Quick Reference)

### Go -> Crystal

| Go | Crystal |
|---|---|
| `package foo` | `module Foo` |
| `const X = 1` | `X = 1_i32` (or exact numeric type) |
| `func F(a string) string` | `def self.f(a : String) : String` |
| `[]byte` | `Bytes` |
| `map[string]int` | `Hash(String, Int32)` |
| `panic("msg")` | `raise "msg"` |
| `*_test.go` | `*_spec.cr` |

### Rust -> Crystal

| Rust | Crystal |
|---|---|
| `mod foo` | `module Foo` |
| `const X: u8 = 1;` | `X = 1_u8` |
| `enum` | `enum` or tagged `struct`/union pattern |
| `Result<T, E>` | exception, union, or explicit result type |
| `Option<T>` | `T?` |
| `#[test]` | `it` blocks in Crystal specs |

Rust-specific translation notes live in:
[references/rust-porting.md](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/references/rust-porting.md)

Port completion checklist and signoff gates live in:
[references/completion-gate.md](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/references/completion-gate.md)

## Completion Criteria

A unit is complete only when all are true:

1. API surface is translated and wired.
2. Relevant upstream tests are ported (or characterization specs added).
3. Crystal gates pass (`format`, `ameba`, `spec`).
4. Parity outputs/fixtures match upstream expectations.
5. Cross-language parity checks pass (see `cross-language-crystal-parity` and
   `references/completion-gate.md`).
6. Documentation reflects completion status and any unavoidable deviations.

## Common Failure Modes

1. Translating to "more idiomatic" behavior that changes semantics.
2. Incorrect numeric width/signedness decisions.
3. Using `String` where binary `Bytes` semantics are required.
4. Porting implementation without parity tests.
5. Forgetting to pin and cite upstream revision used for translation.

## Related Skills

- [crystal-forge-setup-project](/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/SKILL.md)
- [initialize-crystal-porting-project](/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/SKILL.md)
- [cross-language-crystal-parity](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/SKILL.md)
- [find-crystal-shards](/Users/dominic/.agents/skills/crystal_forge/skills/find-crystal-shards/SKILL.md)
- [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal-shard-lib-patch/SKILL.md)
- [bubbletea-port-example-parity](/Users/dominic/.agents/skills/bubbletea-port-example-parity/SKILL.md)
- [bubbletea-parity-workflow](/Users/dominic/.agents/skills/bubbletea-parity-workflow/SKILL.md)
