---
name: bubbletea-go-teatest-golden
description: Generate/update golden outputs from Go Bubble Tea tests using Charm teatest/golden libraries.
---

# Go Teatest Golden

Use this when Go is source-of-truth and tests use Charm teatest/golden.

## Scripts

- Bootstrap deps: [/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/bootstrap_go_module.sh](/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/bootstrap_go_module.sh)
- Run Go teatest update mode: [/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/run_go_teatest_golden.sh](/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/run_go_teatest_golden.sh)
- Raw capture helper (fallback): [/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/generate_go_golden.sh](/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/generate_go_golden.sh)

## Typical

```bash
/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/bootstrap_go_module.sh --workdir <go_dir>
/Users/dominic/.agents/skills/bubbletea-go-teatest-golden/scripts/run_go_teatest_golden.sh --workdir <go_dir> --cmd 'go test ./...'
```

## Local cache workflow

Use local caches in the target repo/workdir to avoid global cache writes:

```bash
source ./scripts/parity_env.sh
./scripts/parity_env.sh --print
```

Or rely on the provided scripts, which already default to local caches:

- `GOCACHE=<workdir>/.cache/go-build`
- `GOMODCACHE=<workdir>/.cache/go-mod`
