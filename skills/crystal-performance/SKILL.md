---
description: Optimize Crystal code for performance by identifying hot code paths first, validating benchmark or profiling infrastructure, comparing against a clean baseline, and keeping only changes that improve verified metrics. Use this skill when users ask about Crystal performance optimization, slow Crystal code, memory usage, hot paths, benchmark-driven cleanup, or allocation-focused tuning in Crystal projects.
metadata:
    github-path: skills/crystal-performance
    github-ref: refs/tags/v1.0.0
    github-repo: https://github.com/dsisnero/crystal_forge
    github-tree-sha: 6a1752a98ff2334167e0f88781a3ccabe586d720
name: crystal-performance
---

# Crystal Performance Optimization Skill

Use this skill to do measured Crystal performance work, not speculative cleanup.

## When to Use This Skill

Use this skill when:

- Users ask for Crystal performance optimization
- A Crystal code review reveals likely allocation or hot-path issues
- Users report slow Crystal code or high memory usage
- Benchmark or profiling results need interpretation
- A repo has a benchmarking plan that should drive the optimization work

## References

Read only what you need:

- [Profiling Tools](references/profiling-tools.md): Instruments.app, perf/callgrind, benchmarking
- [Performance Patterns](references/performance-patterns.md): IO, strings, iterators, structs/tuples, allocation pitfalls
- [Alys Memory Tracer](references/alys.md): allocation tracing with flamegraph/pprof output

## Core Rules

1. Identify the hot code path before changing code.
2. Use the repository's own benchmark or profiling plan if it exists.
3. Validate the benchmark harness itself before trusting any numbers.
4. Compare against a clean baseline when possible.
5. Record both positive and negative benchmark results.
6. Revert or discard changes that do not produce a clear measured win.
7. Keep correctness gates green after every optimization attempt.
8. Organize the work as distinct experiments, not one blended stream of tweaks.
9. For every experiment, keep the exact measured numbers and the comparison point, including failed or regressed attempts.

## Workflow

1. Find the measurement entrypoint.
   Prefer the repo's documented benchmark, profiling command, or performance plan.
   If the repo documents commands that no longer exist, treat that as plan drift and inspect the current benchmark files before proceeding.

2. Make the benchmark runnable.
   If the benchmark harness is stale or broken against the current API, fix the harness first.
   Do not start optimizing runtime code until the measurement path compiles and runs.

3. Capture a baseline.
   Use release mode for timing unless you are explicitly doing trace-friendly profiling.
   When practical, compare the working tree against a clean baseline such as `HEAD`, `main`, or a temporary clean worktree.
   Write down the baseline numbers you will compare against before you start changing code.

4. Identify the hot path.
   Use benchmark output, profiler output, or allocation data.
   Do not optimize broad areas blindly. Name the specific path you are targeting, for example event sync, choose polling, timeout registration, tuple matching, socket framing, or string building.
   Target concrete costs such as repeated scans, intermediate arrays, string churn, closure churn, or unnecessary object creation.

5. Apply the smallest plausible change.
   Favor allocation reduction, simpler data movement, lazy iteration, and avoiding duplicate work.
   Do not widen the change set while the measurement signal is still unclear.

6. Re-measure.
   Run the same benchmark again, ideally against the same baseline and with the same benchmark file.
   Capture before and after numbers for the targeted hot path.
   If the change is flat, noisy, or worse, revert it.

7. Log the experiment outcome.
   Give the experiment a short name or ID.
   Record the hypothesis, the exact code path touched, the measurement command, the baseline number, the new number, and the decision to keep or discard.
   If you revert the change, keep the failed numbers in the log so the same idea is not retried later.

8. Re-run correctness gates.
   Run the focused specs for the touched subsystem at minimum.
   If the repo has lint or broader spec gates available, run them after the measurement confirms a win.

## Decision Rules

Keep a performance change only if at least one of these is true:

- It improves the benchmark or profiler metric you targeted
- It materially reduces allocations on the hot path
- It removes duplicated work on a path that the benchmark confirms matters

Discard a performance change if:

- The benchmark result is flat or worse
- The improvement only appears in synthetic cases but hurts the actual repo benchmark
- The code becomes materially more complex without a measured gain
- You cannot tie the change back to a named hot path

## Crystal-Specific Patterns To Prefer

- Use iterators or `each` chains when they avoid intermediate arrays.
- Pre-size arrays only on hot paths that measurement shows are sensitive.
- Prefer tuples or small structs for fixed-shape transient data.
- Avoid duplicate scans or duplicate decoding work in tight loops.
- Avoid string concatenation churn when writing to IO.
- Be careful with closure allocation in frequently-created events or callbacks.

Read [Performance Patterns](references/performance-patterns.md) when you need detailed guidance.

## Profiling Guidance

- For production-like timing, use `--release`.
- For clearer call trees, start without `--release`, then confirm with `--release`.
- Use Alys only when allocation behavior is the real question and the project can accept the dependency.

Check for Alys with:

```bash
grep -q "alys" shard.yml && echo "installed" || echo "not installed"
```

If Alys is not installed, ask before adding it.

## Deliverables

A good performance pass should end with:

- The exact command used for measurement
- The named hot path that was targeted
- The clean baseline used for comparison, if any
- A list of distinct experiments with enough detail to understand what changed in each one
- The before and after numbers for successful changes
- The failed or flat benchmark results for discarded changes
- The explicit comparison numbers for both the kept and discarded experiments
- The correctness gates that were run
- A clear note when benchmark-plan drift or broken harnesses were fixed as part of the work

Do not report only wins. Negative results are part of the deliverable because they prevent the same bad optimization from being retried later. Every experiment log should preserve the measurement numbers and what they were compared against, not just a summary like "better" or "worse".

## References

- [Crystal Performance Guide](https://crystal-lang.org/reference/1.19/guides/performance.html)
- [Iterator API Documentation](https://crystal-lang.org/api/1.19.1/Iterator.html)
- [Profiling Crystal on OSX (Mike Perham)](https://www.mikeperham.com/2016/06/24/profiling-crystal-on-osx/)
- [Alys — Crystal memory tracer](https://sr.ht/~refi64/alys/)
