---
description: Verify Crystal Bubble Tea output against golden files using Crystal teatest/golden libraries.
name: bubbletea-crystal-teatest-golden
---
# Crystal Teatest Golden

Use this when Crystal specs assert output with `lib/teatest` + `lib/golden`.

## Scripts

- Run Crystal verify mode: [/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/run_crystal_teatest_verify.sh](/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/run_crystal_teatest_verify.sh)
- Raw capture helper (fallback): [/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/generate_crystal_golden.sh](/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/generate_crystal_golden.sh)
- Simple model snapshot helper: [/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/generate_example_golden.sh](/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/generate_example_golden.sh)

## Typical

```bash
/Users/dominic/.agents/skills/bubbletea-crystal-teatest-golden/scripts/run_crystal_teatest_verify.sh \
  --workdir <crystal_dir> \
  --cmd 'crystal spec spec/examples/...'
```

## Local Crystal cache workflow

Use local Crystal cache to avoid global `~/.cache/crystal` writes:

```bash
source ./scripts/parity_env.sh
./scripts/parity_env.sh crystal spec spec/examples/*_parity_spec.cr
```
