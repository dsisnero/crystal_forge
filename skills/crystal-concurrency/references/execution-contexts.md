# Crystal Execution Contexts

Compile with: `crystal build -Dpreview_mt -Dexecution_context program.cr`

## Three Contexts

### ExecutionContext::Parallel

True multi-threaded parallelism. Fibers run on real OS threads simultaneously.

```crystal
ctx = Fiber::ExecutionContext::Parallel.new("workers", 4)

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

Single-threaded, same as default fibers. Useful for logical grouping.

```crystal
ctx = Fiber::ExecutionContext::Concurrent.new("io-group")
ctx.spawn { do_io_work }
```

**Use for**: grouping related I/O fibers without parallelism overhead.

### ExecutionContext::Isolated

One fiber on one dedicated OS thread.

```crystal
gui = Fiber::ExecutionContext::Isolated.new("GUI") do
  Gtk.main
end
gui.wait
```

**Use for**: blocking FFI calls, GUI main loops, C libraries that require
thread-local initialization.

Cannot spawn additional fibers inside — they go to the default context.

## Default Context

Without flags, only the main thread exists. With `-Dpreview_mt -Dexecution_context`,
the default context is `Parallel` with size 1 (behaves like `Concurrent`).

```crystal
Fiber::ExecutionContext.default.size  # => 1
```

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
# Concurrent (default fibers, single thread)
num_workers.times do
  spawn { worker(jobs, results) }
end

# Parallel (real OS threads)
ctx = Fiber::ExecutionContext::Parallel.new("pool", num_workers)
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
    ctx = Fiber::ExecutionContext::Parallel.new("name", thread_count)
    ctx.spawn { cpu_work }

Is it a blocking FFI/C call?
  → ExecutionContext::Isolated
    Fiber::ExecutionContext::Isolated.new("name") { blocking_ffi }

Just want logical grouping?
  → ExecutionContext::Concurrent (one thread, no parallelism)
```

## Shared State Under Parallelism

When using `Parallel`, protect shared mutable state:

- **Atomic** — for counters, flags: `Atomic(Int32).new(0)`
- **Mutex** — for complex state: `mutex.synchronize { hash[k] = v }`
- **Channel** — for communication: channels are thread-safe by design
- **Actor pattern** — one fiber owns state, others send messages via channels

Class variables without `@[ThreadLocal]` are shared across threads:

```crystal
class Foo
  @[ThreadLocal]
  @@counter = 0  # each thread gets its own copy
end
```

## Testing

```bash
crystal spec                                    # default (70 pass)
crystal spec -Dpreview_mt                       # MT fibers (70 pass)
crystal spec -Dpreview_mt -Dexecution_context   # full parallel (73 pass)
```

Use conditional compilation for execution context specs:

```crystal
{% if flag?(:execution_context) %}
  # parallel context tests here
{% else %}
  it "requires MT flags", tags: "parallel" do
    pending!("compile with -Dpreview_mt -Dexecution_context")
  end
{% end %}
```
