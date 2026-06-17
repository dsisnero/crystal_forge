---
name: crystal-concurrency
description: >
  Crystal concurrency and parallelism patterns — fibers, channels, select, WaitGroup,
  ExecutionContext, and porting Go concurrency patterns. Use when implementing any
  concurrent or parallel Crystal code, debugging deadlocks or fiber leaks, choosing
  between spawn and ExecutionContext::Parallel, or translating Go channel patterns
  to Crystal. Covers 31 verified patterns with full runnable examples and measured
  parallel benchmarks (up to 8.76x speedup).
license: MIT
---

# Crystal Concurrency Patterns

Use this skill when implementing concurrency in Crystal — fibers, channels,
select, WaitGroup, parallel execution contexts, or porting Go concurrency
patterns. Also use when debugging deadlocks, fiber leaks, or MT-safety issues
in Crystal code.

## Core Rules

These rules prevent the most common bugs. Violating any of them causes silent
deadlocks, data races, or ambiguous behavior.

1. **`Channel(Bool)` for signaling, never `Channel(Nil)`** — `receive?` uses
   `nil` as the "closed" sentinel. When the payload is `Nil`, you cannot
   distinguish "got a value" from "channel closed". Use `Channel(Bool)` for
   done/quit/semaphore channels.

2. **`receive?` in select for close-safe receives** — `receive` raises
   `ClosedError` when a channel closes inside a `select`. Use `receive?` which
   returns `nil` instead.

3. **`done.close` for broadcast cancellation** — closing a channel wakes ALL
   fibers waiting on `receive?`. This is how you cancel an unknown number of
   workers. Send a value to cancel one; close to cancel all.

4. **`select ... else ... end` = Go's `select { default: }`** — the `else`
   branch fires when no channel operation can complete immediately (non-blocking).

5. **Merge pattern for fan-out under MT** — bare `select when ch.receive` across
   multiple channels that may close raises `ClosedError` under `-Dpreview_mt`.
   Fix: merge outputs with `WaitGroup` + `receive?`.

6. **Double-close is safe** — Crystal silently ignores closing an already-closed
   channel. Go panics. Don't rely on this.

7. **`WaitGroup` is built-in** — `require "wait_group"`. Has `add`, `done`,
   `wait`, and `spawn` methods. Direct equivalent of Go's `sync.WaitGroup`.

## Go-to-Crystal Translation

| Go | Crystal |
|----|---------|
| `go func()` | `spawn { }` |
| `chan T` | `Channel(T)` |
| `make(chan T, n)` | `Channel(T).new(n)` |
| `<-ch` | `ch.receive` |
| `ch <- v` | `ch.send(v)` |
| `close(ch)` | `ch.close` |
| `for v := range ch` | `while v = ch.receive?` |
| `select { case ... }` | `select when ... end` |
| `select { default: }` | `select ... else ... end` |
| `sync.WaitGroup` | `WaitGroup` |
| `time.After(d)` | helper: spawn + sleep + channel send |
| `context.WithCancel` | `Channel(Bool)` + `done.close` |

## Pattern Index

Read `references/patterns.md` for full Crystal code of each pattern.

**Basic**: generator, fan-in, fan-out, pipeline, confinement, for-select loop

**Coordination**: worker pool, bounded parallelism, daisy chain, restore
sequence, ping-pong

**Cancellation**: done channel, quit signal, select timeout, or-channel,
or-done, errgroup, graceful shutdown

**Data flow**: tee channel, bridge channel, ring buffer channel, broadcaster,
pub/sub

**Resilience**: retry with backoff, circuit breaker, rate limiting, bursty rate
limiting, backpressure, batch/debounce

**Computation**: future/promise, first response (racing replicas),
scatter-gather, map-reduce, stateful fiber (actor pattern)

## Execution Context Decision Tree

Read `references/execution-contexts.md` for code examples and benchmarks.

```
Is the work CPU-bound?
├── No (I/O-bound) → default `spawn` (fibers yield on I/O)
└── Yes
    ├── Embarrassingly parallel? → ExecutionContext::Parallel
    │   ctx = Fiber::ExecutionContext::Parallel.new("name", num_threads)
    │   ctx.spawn { work }
    ├── Blocking FFI call? → ExecutionContext::Isolated
    │   Fiber::ExecutionContext::Isolated.new("name") { blocking_call }
    └── Just grouping? → ExecutionContext::Concurrent
        (same as default, one thread, for logical separation)
```

Compile flags: `-Dpreview_mt -Dexecution_context`

**Measured speedups** (Apple Silicon arm64, 8 workers):
- Map-reduce (CPU math): 3.4x with 4 threads
- MD5 hashing (200 items): ~6x with 4 threads
- File digest (1014 files): 8.76x with 8 threads
- Mixed I/O+CPU (2154 files): 4.42x with 8 threads

## MT Safety Checklist

When running specs with `-Dpreview_mt`:

- Channels are thread-safe by design
- WaitGroup is implemented with atomics
- Mutex#synchronize is fiber-safe
- Atomic maps to hardware atomics
- Actor pattern (single fiber owns state) is naturally safe
- **Bare `select` with `receive` on closeable channels** — use `receive?` or
  merge pattern
- **Shared mutable state without locks** — add Mutex or Atomic
- **Timing-sensitive assertions** — add tolerance, thread scheduling is
  non-deterministic

## References

- `references/channel-rules.md` — closed channels, nil channels, Channel(Nil)
  ambiguity, receive vs receive?, MT behavior findings with before/after code
- `references/patterns.md` — all 31 patterns with Crystal code examples
- `references/execution-contexts.md` — Parallel, Concurrent, Isolated with
  benchmarks, worker pool and map-reduce examples

## Full Examples

Read these when implementing a complex pattern — they show complete wiring
(producer → channel → workers → WaitGroup → results → close lifecycle):

- `examples/worker_pool.cr` — producer→jobs→workers→results with spawn vs
  ctx.spawn benchmark. The template for any worker pool.
- `examples/parallel_digest.cr` — walk directory, hash files, benchmark
  default vs ExecutionContext::Parallel. Real-world bounded parallelism.
- `examples/actor.cr` — stateful fiber with read/write request channels,
  concurrent readers and writers, clean shutdown.
- `examples/errgroup.cr` — run N tasks, cancel all on first error via
  done.close, capture first exception.
- `examples/pipeline_cancel.cr` — gen→square→filter pipeline with done
  channel through every stage, fan-out/fan-in with merge, early consumer exit.
- `examples/pubsub.cr` — PubSub class with subscribe/unsubscribe/publish,
  Mutex-protected subscriber map, topic routing, clean shutdown.
