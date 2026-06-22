---
name: crystal-concurrency
description: >
  Crystal concurrency and parallelism patterns — fibers, channels, select, WaitGroup,
  ExecutionContext, and porting Go concurrency patterns. Use when implementing any
  concurrent or parallel Crystal code, debugging deadlocks or fiber leaks, choosing
  between spawn and ExecutionContext::Parallel, or translating Go channel patterns
  to Crystal. Covers 41 patterns across 6 categories, ported from Go and verified
  against an upstream spec suite, with runnable examples and measured parallel
  benchmarks (up to 8.76x speedup).
license: MIT
---

# Crystal Concurrency Patterns

Use this skill when implementing concurrency in Crystal — fibers, channels,
select, WaitGroup, parallel execution contexts, or porting Go concurrency
patterns. Also use when debugging deadlocks, fiber leaks, or MT-safety issues
in Crystal code.

If the user asks whether the concurrency is actually faster, wants throughput
numbers, worker-count comparisons, hotspot validation, or says not to guess,
also use `crystal-benchmarking`.

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

41 patterns ported from `dsisnero/crystal-concurrency-patterns` (the Crystal port of
lotusirous' Go Concurrency Patterns) and split across six category reference files.
Open the file for the category you need — each entry has fuller, self-contained
Crystal code, the gotcha that bites people, and a citation to the upstream spec
(characterized) or src/example (demonstrated) it came from. The self-contained
code blocks type-check under Crystal 1.20.2 (the Subscription entry is an annotated
sketch of the nil-channel workaround, not a standalone program).

Patterns marked with an example file have a complete runnable program in `examples/`
showing the full lifecycle (producer → channel → workers → WaitGroup → close).

### Basic — `references/basic.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Generator | Fiber + channel; the channel is the stream | — |
| Fan-In | Merge N input channels into one (WaitGroup close) | — |
| Fan-Out | N workers compete on one source; each value goes to one | — |
| Pipeline | Chain stages, each closing its outbound channel | `pipeline_cancel.cr` |
| Confinement | One fiber owns the data; publish via channel | — |
| For-Select Loop | Long-lived fiber polling `done` with `select/else` | — |
| Repeat / Take | Composable infinite generator bounded by `take` | — |
| Error-Handling Channel | Carry value-or-error so a stage never crashes | — |

### Coordination — `references/coordination.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Worker Pool | Fixed workers pull jobs, WaitGroup closes results | `worker_pool.cr` |
| Bounded Parallelism | Fixed pool walks a tree with `done` cancellation | `parallel_digest.cr` |
| Queuing (Semaphore) | Buffered `Channel(Bool)` caps concurrency | — |
| Daisy Chain | N fibers relay a token in a line | — |
| Restore Sequence | Per-message `wait` channel restores ordering | — |
| Ping-Pong | Volley one mutable object; ownership moves with send | — |

### Cancellation — `references/cancellation.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Done Channel | `close` broadcasts cancel to all waiters | `pipeline_cancel.cr` |
| Quit Signal | Two-way stop: request + acknowledge | — |
| Or-Channel | Merge signals; fire when any input closes | — |
| Or-Done | Wrap a value channel so reads respect `done` | — |
| Errgroup | Cancel siblings on first error, return it | `errgroup.cr` |
| Graceful Shutdown | Ordered teardown: done → jobs → wait | — |
| Select Timeout | Bound a receive with `select ... when timeout(span)` | — |
| Context | `done` + cancel proc = WithCancel / WithTimeout | — |

### Data Flow — `references/data-flow.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Tee Channel | Duplicate each value to two outputs (flag workaround) | — |
| Bridge Channel | Flatten a channel-of-channels into one stream | — |
| Ring Buffer | Keep last N, drop oldest (Deque, not `select/else`) | — |
| Broadcaster | Every subscriber gets every message | — |
| Pub/Sub | Topic-routed broadcaster with Mutex-guarded map | `pubsub.cr` |
| Subscription | RSS aggregator; the nil-channel-in-select workaround | — |

### Resilience — `references/resilience.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Rate Limiting | One op per fixed interval | — |
| Bursty Rate Limiting | Token bucket allowing short bursts | — |
| Retry with Backoff | Exponential delays between attempts | — |
| Circuit Breaker | Fail fast after N failures; cool down; half-open | — |
| Backpressure | Bounded channel buffer is the flow control | — |
| Batch / Debounce | Flush on size or on a quiet window | — |

### Computation — `references/computation.md`
| Pattern | What it does | Example |
|---------|--------------|---------|
| Future / Promise | Start work now, collect later (cap-1 channel) | — |
| First Response | Race replicas, take fastest (buffered, no leak) | — |
| Scatter-Gather | Fan out, gather until one shared deadline | — |
| Map-Reduce | Parallel map, sequential reduce | — |
| Stateful Fiber (Actor) | One fiber owns state; access via request channels | `actor.cr` |
| Ticker with Cancellation | Tick on interval until `done` | — |
| Mutex-Protected State | Guarded counter/map when an Actor is overkill | — |

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

Do not jump to `ExecutionContext` because a path "looks parallelizable". Measure
the current path first and identify whether the real cost is I/O, parser work,
FFI, cache persistence, or actual CPU-bound computation.

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
- Pattern reference files (full code + gotchas + source citations), one per
  category in the index above:
  `references/basic.md`, `references/coordination.md`, `references/cancellation.md`,
  `references/data-flow.md`, `references/resilience.md`, `references/computation.md`
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
