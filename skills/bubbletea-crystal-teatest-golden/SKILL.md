---
name: bubbletea-crystal-teatest-golden
description: Verify Crystal Bubble Tea output against existing `teatest`/`golden` fixtures. Use when Crystal is the side being checked against a known oracle and specs already rely on `lib/teatest` or `lib/golden`.
---

# Crystal Teatest Golden

Use this skill when the Crystal repo already has golden fixtures and the job is
to verify Crystal output, not define the oracle.

## Scripts

- `scripts/run_crystal_teatest_verify.sh`: default verification path
- `scripts/generate_crystal_golden.sh`: raw capture fallback
- `scripts/generate_example_golden.sh`: snapshot helper for simple examples

## Default flow

1. Prefer `scripts/run_crystal_teatest_verify.sh`.
2. Run Crystal specs against existing goldens.
3. Use raw capture only when the teatest harness is missing or broken.
4. Treat Crystal-generated output as evidence, not as the source-of-truth oracle.

## Typical command

```bash
./scripts/run_crystal_teatest_verify.sh \
  --workdir <crystal_dir> \
  --cmd 'crystal spec spec/examples/...'
```

## Guardrails

- Keep Crystal cache local to the repo when possible.
- Prefer deterministic message injection over timing-heavy waits.
- If the golden oracle needs to be created or refreshed from Go, route to
  `bubbletea-go-teatest-golden` first.
