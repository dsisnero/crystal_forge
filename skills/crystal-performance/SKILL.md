---
name: crystal-performance
description: Optimize Crystal code with measurement, not guesswork. Use when users report slow code, high allocations, hot-path regressions, or when a Crystal benchmark or profile needs action.
---

# Crystal Performance

Use this skill for measured optimization work only.

Read the bundled references only as needed:

- `references/profiling-tools.md`
- `references/performance-patterns.md`
- `references/alys.md`

## Rules

1. Identify the hot path before changing code.
2. Fix a broken benchmark harness before optimizing runtime code.
3. Capture a clear baseline and compare against it.
4. Treat each optimization as a separate experiment.
5. Keep failed or flat results; they are part of the deliverable.
6. Revert or discard changes without a measured win.
7. Re-run correctness gates after every kept change.

## Workflow

### 1. Find the measurement entrypoint

Prefer the repo's own benchmark, profile, or performance plan. If the documented
command is stale, repair the harness first.

### 2. Capture a baseline

Use release mode for timing unless you specifically need a debug-friendly call
tree. Write down the exact command and the number you will compare against.

### 3. Name the hot path

Target one concrete cost such as allocation churn, duplicate scans, string
building, closure creation, or expensive decoding.

### 4. Apply the smallest plausible change

Prefer less allocation, less copying, simpler data movement, and less repeated
work. Avoid broad refactors while the signal is still unclear.

### 5. Re-measure and decide

Keep a change only if it measurably improves the targeted benchmark or
allocation profile. Otherwise revert it and record the result.

### 6. Re-run correctness gates

Run focused specs first, then broader gates if the repo has them.

## Deliverable

Report:

- the exact measurement command
- the named hot path
- the baseline used
- each experiment and what changed
- before/after numbers for kept changes
- flat or regressed numbers for discarded changes
- the correctness gates that ran

## Notes

- Use `alys` only when allocation tracing is the actual question.
- If `alys` is not already present in `shard.yml`, ask before adding it.
