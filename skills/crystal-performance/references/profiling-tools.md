# Crystal Profiling Tools

## Compilation Flags

```bash
crystal build --release program.cr  # Optimized build for production profiling
crystal compile program.cr         # Compile without --release (clearer traces)
crystal run --release program.cr   # Run with optimizations
```

Use `crystal compile` (not `crystal build`) when you only need the binary
and don't want to run it — useful when handing the binary to a profiling tool.

**`--release` tradeoff:** Compile with `--release` when profiling production
code so you measure the same binary you run in production. However, traces
are much easier to read *without* `--release` because LLVM won't inline
method calls — useful for initial exploration and understanding call paths.

---

## macOS: Instruments.app

Crystal uses LLVM, so Instruments.app (part of Xcode) works with Crystal
binaries out of the box — no custom profiling APIs or runtime support needed.

### Installation

```bash
brew update
brew install crystal-lang
```

Instruments.app is included with Xcode. If you have Xcode installed, Instruments is already available.

### Step-by-Step Workflow

**1. Compile your program:**

```bash
crystal compile app.cr
```

Use `--release` for production-profiling parity, or omit it for easier-to-read traces (LLVM won't inline method calls).

**2. Profile with the Time Profiler:**

```bash
instruments -t "Time Profiler" ./app
```

Output: `Instruments Trace Complete (Duration : 4.46s; Output : /Users/me/instrumentscli0.trace)`

**3. Open the trace:**

```bash
open instrumentscli0.trace/
```

This launches Instruments.app with a tree view where you can drill down from
`main` into each function call, showing the percentage of time spent in
every method.

### Available Instruments Modes

| Mode | What it tracks |
|------|---------------|
| `"Time Profiler"` | CPU time per function (most common) |
| `"Allocations"` | Memory allocations and heap usage |
| `"Leaks"` | Memory leaks |
| `"System Trace"` | Syscalls, context switches, I/O |
| `"File Activity"` | File system operations |
| `"Activity Monitor"` | Overall process resource usage |

To use a different mode, change the `-t` argument:

```bash
instruments -t "Allocations" ./app
instruments -t "System Trace" ./app
```

### Interpreting the Trace

The Instruments tree view shows:

- A top-down call tree starting from `main`
- The percentage of total runtime spent in each function
- Symbols from your Crystal source mapped to compiled code

Example: In a loop calling `foo(i)` where `foo` does `"mike" + i.to_s`,
~80% of time appears under `Int32#to_s` and `String#+` — directly
identifying the hot paths.

---

## Linux

### perf

```bash
perf record ./app && perf report
```

### callgrind

```bash
valgrind --tool=callgrind ./app && kcachegrind callgrind.out.*
```

Both work with Crystal binaries since Crystal uses LLVM.

---

## Benchmarking

Use Crystal's `Benchmark` module:

```crystal
require "benchmark"

Benchmark.ips do |x|
  x.report("fast") { fast_implementation }
  x.report("slow") { slow_implementation }
end
```
