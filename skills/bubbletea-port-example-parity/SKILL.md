---
name: bubbletea-port-example-parity
description: Fix Bubble Tea parity at the example layer by matching Go example behavior, harness inputs, and view output. Use when drift is caused by example code rather than runtime or shard internals.
---

# Bubble Tea Example Port Parity

Own example-level parity only: `model`, `init`, `update`, `view`, and harness
setup.

## Route away when needed

- Need orchestration or capture commands: `bubbletea-parity-workflow`
- Need Go golden generation: `bubbletea-go-teatest-golden`
- Need Crystal verification: `bubbletea-crystal-teatest-golden`
- Drift is in `src/` or `lib/`, not the example: `crystal-shard-lib-patch` or
  the repo's runtime code path

## Checklist

1. Match Go state shape and `init` / `update` / `view` semantics.
2. Match the deterministic input sequence and quit behavior.
3. Match window sizing and other harness assumptions.
4. Keep runnable examples guarded with `if PROGRAM_NAME == __FILE__`.
5. Verify against Go-generated fixtures, not Crystal-generated ones.

## Guardrails

- Prefer explicit messages over sleeps and timing tricks.
- Keep temporary harness files under `temp/`.
- If the example logic already matches Go, stop patching the example and move
  the bug to runtime or shard ownership.
