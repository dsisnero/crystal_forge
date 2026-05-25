---
name: bubbletea-go-teatest-golden
description: Generate or refresh Go Bubble Tea golden fixtures when Go is the source of truth and tests use Charm `teatest` or `golden`.
---

# Go Teatest Golden

Use this skill when Go owns the canonical terminal output and you need fresh
`*.golden` artifacts for downstream Crystal parity checks.

## Scripts

- `scripts/bootstrap_go_module.sh`: install module dependencies locally
- `scripts/run_go_teatest_golden.sh`: default golden update path
- `scripts/generate_go_golden.sh`: raw capture fallback

## Default flow

1. Bootstrap the Go workdir if needed.
2. Run the Go teatest update command to regenerate goldens.
3. Sync those goldens into the Crystal repo before Crystal verification.
4. Use raw capture only when no teatest harness exists.

## Typical commands

```bash
./scripts/bootstrap_go_module.sh --workdir <go_dir>
./scripts/run_go_teatest_golden.sh --workdir <go_dir> --cmd 'go test ./...'
```

## Guardrails

- Keep `GOCACHE` and `GOMODCACHE` local to the workdir when possible.
- Do not treat Crystal output as an oracle when Go fixtures are available.
- If the task is only Crystal-side verification, route to
  `bubbletea-crystal-teatest-golden`.
