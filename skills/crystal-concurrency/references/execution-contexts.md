# Crystal Execution Contexts

Crystal 1.21 enables execution contexts by default. No preview compiler flags are
needed. The default context has parallelism 1; resize it explicitly or create a
`Parallel` context to execute CPU work in parallel.

## Three Contexts

### ExecutionContext::Parallel

True multi-threaded parallelism. Fibers can run on real OS threads
simultaneously. The capacity is a maximum, not a fixed set of dedicated threads.
Contexts autoscale up to that capacity. Too many simultaneously blocking fibers
can exhaust it and stall remaining work; bound blocking work with a semaphore or
use another context.

```crystal
ctx = Fiber::ExecutionContext::Parallel.new("workers", maximum: 4)

wg = WaitGroup.new(data.size)
data.each do |val|
  ctx.spawn do        # <-- spawns onto parallel context
    ch.send(work(val))
    wg.done
  end
end
wg.wait
```

**Use for**: CPU-bound work (hashing, math, compression, image processing).

**Requires**: `Atomic` or `Mutex` for any shared mutable state.

**Resize at runtime**:
```crystal
ctx.resize(new_count)
```

### ExecutionContext::Concurrent

A dedicated non-parallel context. It is not the default context.

```crystal
ctx = Fiber::ExecutionContext::Concurrent.new("io-group")
ctx.spawn { do_io_work }
```

**Use for**: grouping related work that must never run in parallel with itself.
It may run in parallel with other contexts. A blocking fiber blocks this entire
context.

### ExecutionContext::Isolated

One fiber owns one OS thread for its lifetime. The thread can be reused after
the fiber terminates.

```crystal
gui = Fiber::ExecutionContext::Isolated.new("GUI") do
  Gtk.main
end
gui.wait
```

**Use for**: a task that intentionally blocks its system thread for a long time,
or needs a dedicated reactive loop (for example, GUI main loops). Its event loop
and cross-context `Channel`, `WaitGroup`, and `Sync` communication still work;
when its fiber waits, the thread pauses. Blocking its owned thread does not
impact other contexts.

An isolated fiber cannot spawn more fibers in its own context. Configure a
`spawn_context:` when creating it, or use another context's `spawn` method:

```crystal
workers = Fiber::ExecutionContext::Concurrent.new("workers")
main = Fiber::ExecutionContext::Isolated.new("GUI", spawn_context: workers) do
  spawn { refresh_worker_state }
end
main.wait
```

## Default Context

The runtime starts the main fiber in `Fiber::ExecutionContext.default`, a
`Parallel` context with parallelism 1. It is therefore single-threaded by default,
but not equivalent to `Concurrent`.

```crystal
default = Fiber::ExecutionContext.default
default.resize(Fiber::ExecutionContext.default_workers_count)
```

Outside an `Isolated` context, `spawn` uses the current fiber's context. Use
`ctx.spawn` to target another context. A fiber does not migrate between contexts, but `Parallel` and
`Concurrent` fibers are not pinned to an OS thread and may resume on a different
one. Avoid `@[ThreadLocal]` and do not preserve thread-local assumptions across
yields.

## Benchmarks (Apple Silicon arm64)

### Map-Reduce (CPU math, 8 items × 2M iterations)

```
Default spawn:                          49ms
ExecutionContext::Parallel (4 threads):  14ms
Speedup:                                3.4x
```

### Worker Pool MD5 (200 items)

```
Default spawn:                          5.7ms
ExecutionContext::Parallel (4 threads):  0.9ms
Speedup:                                ~6x
```

### File Digest (1014 files, 8 workers)

```
Default spawn:                          719ms
ExecutionContext::Parallel (8 threads):   82ms
Speedup:                                8.76x
```

### Mixed I/O + CPU (2154 files, 8 workers)

```
Default spawn:                         1109ms
ExecutionContext::Parallel (8 threads):  251ms
Speedup:                                4.42x
```

CPU-dominated workloads scale near-linearly. Mixed I/O+CPU is limited by
filesystem throughput.

## Worker Pool: spawn vs ctx.spawn

The only API change to go from concurrent to parallel:

```crystal
# Concurrent work in the current context
num_workers.times do
  spawn { worker(jobs, results) }
end

# Parallel (real OS threads)
ctx = Fiber::ExecutionContext::Parallel.new("pool", maximum: num_workers)
num_workers.times do
  ctx.spawn { worker(jobs, results) }
end
```

Same worker code, same channels, same WaitGroup. Just `ctx.spawn` instead of
`spawn`.

## Decision Guide

```
Is the work I/O-bound?
  → default spawn (fibers yield on I/O naturally)

Is the work CPU-bound?
  → ExecutionContext::Parallel
    ctx = Fiber::ExecutionContext::Parallel.new("name", maximum: thread_count)
    ctx.spawn { cpu_work }

Does one task need to own a system thread for its lifetime?
  → ExecutionContext::Isolated
    Fiber::ExecutionContext::Isolated.new("name") { dedicated_loop }

Just want logical grouping?
  → ExecutionContext::Concurrent (one scheduler; one fiber at a time within
    this context)
```

## Shared State Under Parallelism

When using `Parallel`, protect shared mutable state:

- **Atomic** — for counters, flags: `Atomic(Int32).new(0)`
- **Mutex** — for complex state: `mutex.synchronize { hash[k] = v }`
- **Channel** — for communication: channels are thread-safe by design
- **Actor pattern** — one fiber owns state, others send messages via channels

Class variables are shared across threads. Keep their values immutable after
initialization, or protect reads and writes with `Sync`/`Mutex`. Avoid
`@[ThreadLocal]`: `Parallel` and `Concurrent` fibers may resume on another
system thread.

## Testing

```bash
crystal spec
```

Exercise explicit `Parallel` contexts in tests that access shared mutable state.
Keep scheduling-sensitive assertions tolerant, and run race-prone code under
repeated parallel load.

Sources: [Crystal 1.21 Parallelism guide](https://crystal-lang.org/reference/1.21/guides/parallelism.html),
[ExecutionContext API](https://crystal-lang.org/api/1.21.0/Fiber/ExecutionContext.html),
and [release notes](https://crystal-lang.org/2026/07/16/1.21.0-released/).
