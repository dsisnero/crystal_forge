---
name: crystal-benchmarking
description: Build or repair Crystal benchmark harnesses and use them to measure throughput, latency, concurrency scaling, and hotspot location with real numbers. Use whenever the user asks for benchmarks, speedup data, throughput comparisons, worker-count comparisons, concurrency validation, hotspot analysis, or says not to guess about performance.
---

# Crystal Benchmarking

Use this skill when the question is not "how should this be structured?" but
"what does the runtime actually do?".

This skill is specifically for:

- proving whether a concurrency change improves throughput
- comparing sequential vs bounded-concurrent vs async return paths
- identifying the real hotspot before changing more code
- measuring worker-count scaling such as `x1`, `xN`, or `sequential` baselines
- separating return latency from deferred/background work latency

If the task is general optimization, also read `crystal-performance`.
If the task is about concurrency architecture or channel/fiber correctness,
also read `crystal-concurrency`.

## What this skill is for

Benchmarking is a separate discipline from both optimization and concurrency
design. A code path can be:

- concurrent but slower
- asynchronous at the API boundary but still throughput-neutral
- structurally elegant but not a hotspot
- flat in microbenchmarks and still valuable for tail latency

Do not infer wins from code structure alone.

## Core rules

1. Measure the real path, not a toy helper, unless the helper itself is the question.
2. Always compare against a named baseline.
3. Run at least 3 times and discard the cold run unless the cold path itself matters.
4. Distinguish throughput from return latency.
5. Distinguish concurrency from parallelism.
6. Keep flat or regressed results; they are part of the outcome.
7. If a benchmark takes too long to be useful, parameterize it instead of guessing.

## Benchmark questions to answer

Every benchmark pass should explicitly answer one or more of:

- Is this code actually a hotspot?
- Does bounded concurrency help at all?
- At what worker count does it flatten or regress?
- Is the win in total throughput, return latency, or both?
- Is the dominant cost file I/O, parsing, extraction, FFI, serialization, or cache persistence?

## Standard comparison set

For concurrency-sensitive code, prefer this comparison matrix:

- `sequential`
- `concurrent x1`
- `concurrent xN`
- `async return`
- `async flush` or `background completion`

Use only the rows that make sense for the path.

Examples:

- file prep: `sequential`, `x1`, `xN`
- discovery/extraction: `sequential baseline`, `pipeline x1`, `pipeline xN`
- async cache write: `return latency`, `flush latency`

## Harness design

### Parameterize size

Benchmarks should be controllable with environment variables or arguments:

- file count
- payload size
- worker count
- run count
- section selection

This lets you shrink the run to get signal quickly, then scale up the hot path.

### Isolate sections

If one section dominates the run, make benchmark sections selectable so you can
rerun only:

- file I/O
- search prep
- discovery
- extract graph
- cache flush

### Keep fixture generation deterministic

Use generated local fixtures where possible:

- fixed file counts
- fixed method/function counts
- stable names
- no network

## Concurrency-specific guidance

### File I/O

Do not assume concurrent file reads are a win. On fast local disks they are
often flat or slightly worse. Measure before keeping that complexity.

### Discovery and extraction

This is often where the real cost lives: parser setup, tree-sitter parse,
query execution, AST walking, symbol extraction.

If file I/O is flat but discovery is slow, stop micro-optimizing readers and
benchmark parser/extractor stages directly.

### Async persistence

For cache or snapshot writes, measure two numbers:

- how fast the caller returns
- how long flush/background completion takes

If return latency improves materially and flush stays bounded, async persistence
may still be worthwhile even when total work is unchanged.

### CPU-bound work

If bounded fibers show only small gains on a CPU-heavy path, benchmark whether
the bottleneck is actually parallelizable before reaching for
`ExecutionContext::Parallel`.

## Output format

Always report:

- exact benchmark command
- fixture size and worker count
- baseline and comparison rows
- average warm time and cold time
- what the numbers imply
- next action based on the data

Use direct conclusions such as:

- "file I/O is not the hotspot"
- "search prep is flat; do not optimize this next"
- "discovery dominates runtime and current concurrency only buys ~12%"
- "async cache improves return latency but not total work"

## When to stop

Stop benchmarking and switch back to implementation when:

- one hotspot clearly dominates
- a proposed optimization target has measurable headroom
- a concurrency feature is shown to be flat or regressive

At that point, the benchmark result becomes the gate for the next code change.
