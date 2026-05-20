---
description: Implement example-level Go-to-Crystal Bubble Tea parity by matching model/update/view behavior and deterministic harness inputs. Use when parity drift is owned by example logic rather than runtime/shard internals.
metadata:
    github-path: skills/bubbletea-port-example-parity
    github-ref: refs/tags/v1.0.0
    github-repo: https://github.com/dsisnero/crystal_forge
    github-tree-sha: f4307615b8dfdad7b962af676d6d93e9d8e8577b
name: bubbletea-port-example-parity
---

# Bubble Tea Example Port Parity

## Goal

Own parity fixes at the example layer (`model`, `update`, `view`, harness setup)
when example behavior is not yet faithful to Go.

## Ownership Boundary

Use this skill for example-level behavior only.

Delegate to companion skills when needed:

- Orchestration and route selection: [bubbletea-parity-workflow](/Users/dominic/.agents/skills/bubbletea-parity-workflow/SKILL.md)
- Go golden generation: [bubbletea-go-teatest-golden](/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/SKILL.md)
- Crystal golden verification: [bubbletea-crystal-teatest-golden](/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/SKILL.md)
- Runtime/shard drift under `lib/`: [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal-shard-lib-patch/SKILL.md)

## Routing Matrix

| Trigger | Action |
|---|---|
| Message ordering, state transitions, or view output differ from Go example | Patch example logic/harness in this repo |
| Example logic already matches Go but output still drifts | Escalate to runtime/shard fix (`src/` or `lib/`) |
| Teatest/golden harness is absent | Use `run_parity.sh` temporarily, then add teatest/golden coverage |

## Example-Level Checklist

1. Match Go model state and `init/update/view` semantics exactly.
2. Match deterministic input/event sequence and quit behavior.
3. Match window sizing and environment assumptions.
4. Keep runnable Crystal examples guarded with `if PROGRAM_NAME == __FILE__`.
5. Verify against Go-generated golden fixtures (not Crystal-generated oracles).

## Determinism Rules

- Prefer explicit message injection (key/mouse/tick/frame) over ambient timing.
- Avoid unbounded sleeps; if required, keep them minimal and symmetric with Go.
- Keep temporary harness artifacts in `temp/` (or `$PARITY_TEMP_DIR`).

## Execution Handoff

Run orchestration and capture commands from
[bubbletea-parity-workflow](/Users/dominic/.agents/skills/bubbletea-parity-workflow/SKILL.md).
This skill should not duplicate command ownership; it owns only example-level
behavior decisions and fixes.
