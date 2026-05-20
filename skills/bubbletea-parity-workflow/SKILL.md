---
description: Orchestrate Bubble Tea Go-vs-Crystal parity work by routing to teatest/golden generation, Crystal verification, and fallback byte diagnostics. Use when parity work spans multiple steps or requires choosing the correct parity path and subskill handoffs.
name: bubbletea-parity-workflow
---
# Bubble Tea Parity Workflow

## Goal

Coordinate parity verification across Bubble Tea Go and Crystal implementations.

Default path is teatest/golden. Raw byte comparison is fallback only.

## Ownership

This skill is the orchestrator. It does not own all implementation details.

Subskills own execution details:

- Go golden generation: [bubbletea-go-teatest-golden](/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-go-teatest-golden/SKILL.md)
- Crystal golden verification: [bubbletea-crystal-teatest-golden](/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-crystal-teatest-golden/SKILL.md)
- Example-level parity behavior rules: [bubbletea-port-example-parity](/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-port-example-parity/SKILL.md)
- Shard patch workflow when drift is under `lib/`: [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal_forge/skills/crystal-shard-lib-patch/SKILL.md)

## Routing Matrix

| Trigger | Route | Output |
|---|---|---|
| Need canonical parity flow with existing teatest harnesses | `run_teatest_golden_mode.sh` + Go/Crystal subskills | Updated Go goldens + Crystal verify result |
| Need Go golden creation/update only | `bubbletea-go-teatest-golden` | Fresh Go `*.golden` artifacts |
| Need Crystal verification only | `bubbletea-crystal-teatest-golden` | Crystal spec parity verdict |
| No teatest/golden harness available but both Go and Crystal capture paths exist | Repo-local capture scripts + `run_parity.sh` fallback | Cached local binaries plus `go.golden`/`crystal.golden` diagnostics |
| Crystal-only example verification with no upstream Go harness/oracle | Temporary Crystal `teatest` harness under `temp/` | Runtime verdict clearly labeled as smoke verification, not parity |
| Drift traced to shard code under `lib/` | `crystal-shard-lib-patch` | Local shard patch + upstream traceability |
| Drift traced to example behavior mismatch | `bubbletea-port-example-parity` | Example-model parity fix |

## Default Orchestration Flow

1. Run Go golden update (`GOLDEN_UPDATE=1`).
2. Sync generated `*.golden` files into Crystal testdata.
3. Run Crystal verification (`GOLDEN_UPDATE=0`).

Use:

```bash
/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-parity-workflow/scripts/run_teatest_golden_mode.sh \
  --go-workdir <go_dir> \
  --go-update-cmd '<go teatest command>' \
  --sync-goldens-from <go_golden_dir> \
  --sync-goldens-to <crystal_golden_dir> \
  --crystal-workdir <crystal_dir> \
  --crystal-verify-cmd '<crystal spec command>'
```

## Repo-Local Capture Workflow

When you need parity capture without escalation for cache or binary writes, use repo-local scripts and keep all artifacts under `./temp/`. If the Go module cache is cold, the first Go build still needs normal network access to download modules:

```bash
bash ./scripts/parity_env.sh --print
bash ./scripts/capture_go_golden.sh \
  --workdir vendor/huh/examples \
  --source <go-file> \
  --name <binary-name> \
  --out temp/goldens/<name>.golden
bash ./scripts/capture_crystal_golden.sh \
  --source <crystal-file> \
  --name <binary-name> \
  --out temp/goldens/<name>.golden
```

Cache layout:

- `./temp/cache/crystal`
- `./temp/cache/go-build`
- `./temp/cache/go-mod`
- `./temp/cache/bin`
- `./temp/goldens`
- `./temp/parity`

For deterministic spec authoring, prefer repo-local helpers such as `spec/parity_capture_helper.cr` to drive `form.init`, `WindowSizeMsg`, and child commands before asserting with `Golden.require_equal(...)`.

## Fallback Path

Use only when teatest/golden harnesses do not exist and both sides can still be captured:

```bash
/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-parity-workflow/scripts/run_parity.sh <args>
```

This emits raw parity diagnostics (`go.golden`, `crystal.golden`, base64,
sha256) and should be treated as temporary evidence until teatest/golden
coverage exists.

## Shared Guardrails

1. Keep example behavior faithful to Go; do not change examples only to force fixture parity.
2. If no Go oracle exists, do not claim parity. Use a temporary Crystal `teatest` harness and label the result as smoke verification only.
3. If example logic matches Go and drift remains, fix runtime/shard behavior in `src/` or `lib/`.
4. Prefer deterministic message injection over sleep-driven timing.
5. `Teatest.wait_for(tm.output, ...)` reads a streaming output buffer, not a stable full-screen snapshot. Repeated waits should look for the next expected redraw, and final assertions should prefer model state or a final captured output.
6. Keep temporary captures in `temp/` (or `$PARITY_TEMP_DIR`) and clean them.
7. Use local cache wrappers (`scripts/parity_env.sh`) to avoid global cache permissions.
8. If parity capture is blocked by sandbox/network constraints, rerun with escalation and continue.

## Commands

Local cache wrapper:

```bash
source ./scripts/parity_env.sh
bash ./scripts/parity_env.sh --print
bash ./scripts/parity_env.sh crystal spec spec/examples/*_parity_spec.cr
```

Fallback diagnostics runner:

```bash
/Users/dominic/.agents/skills/crystal_forge/skills/bubbletea-parity-workflow/scripts/run_parity.sh --help
```

## Completion Criteria

1. Go oracle artifacts are fresh for the exact harness/options under test.
2. Crystal verification passes against synced goldens.
3. Any remaining mismatch has a clear owner (`example`, `src`, or `lib`).
4. Temporary capture artifacts are cleaned or intentionally retained.
