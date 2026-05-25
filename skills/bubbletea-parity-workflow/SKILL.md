---
name: bubbletea-parity-workflow
description: Orchestrate Bubble Tea Go-vs-Crystal parity work. Use when you need to choose between Go golden generation, Crystal verification, example-layer fixes, shard fixes, or raw diagnostic fallback.
---

# Bubble Tea Parity Workflow

This skill is the router for Bubble Tea parity work. It decides the path; the
companion skills own the detailed implementation.

## Route first

- Need fresh Go goldens: use `bubbletea-go-teatest-golden`.
- Need Crystal verification against existing goldens: use
  `bubbletea-crystal-teatest-golden`.
- Drift is in example `model` / `update` / `view` / harness code: use
  `bubbletea-port-example-parity`.
- Drift is under `lib/`: use `crystal-shard-lib-patch`.
- No teatest harness exists on either side: use the raw fallback scripts here,
  then add proper golden coverage.

## Default flow

1. Refresh Go goldens.
2. Sync the generated `*.golden` files into the Crystal repo.
3. Run Crystal verification against the synced fixtures.
4. Assign any remaining mismatch to `example`, `src`, or `lib`.

```bash
./scripts/run_teatest_golden_mode.sh \
  --go-workdir <go_dir> \
  --go-update-cmd '<go teatest command>' \
  --sync-goldens-from <go_golden_dir> \
  --sync-goldens-to <crystal_golden_dir> \
  --crystal-workdir <crystal_dir> \
  --crystal-verify-cmd '<crystal spec command>'
```

## Fallback path

Use `scripts/run_parity.sh` only when a proper teatest/golden harness does not
exist yet. Treat its byte-level output as temporary diagnostics, not final
parity evidence.

## Guardrails

- Keep example behavior faithful to Go; do not edit examples just to match a
  fixture.
- If no Go oracle exists, label the result as smoke verification rather than
  parity.
- Prefer deterministic message injection over sleep-driven timing.
- Keep temporary captures and caches under `temp/`.
- If cache or module writes are blocked, rerun with escalation rather than
  inventing a different workflow.

## Completion

Parity work is ready to close when:

1. The Go oracle matches the harness under test.
2. Crystal verification passes against the synced fixtures.
3. Any remaining mismatch has a clear owner.
