# Alys — Crystal Memory Usage Tracer

**Alys** is a Crystal memory usage tracer that tracks memory allocs,
re-allocs, and frees for later analysis. It produces `.alys` binary trace
files that can be converted to JSON, Google pprof, folded stacks, or
flamegraphs.

**NOTE: Alys is alpha-quality software.** Expect rough edges.

---

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  alys:
    git: https://git.sr.ht/~refi64/alys
```

2. Run `shards install`

### libunwind (Linux performance)

On Linux, the default glibc unwind implementation is significantly slower
than alternatives. Alys tries to use LLVM's libunwind if available.
Install it:

```bash
# Any distro — build local copy
lib/alys/tools/build_libunwind.sh

# Fedora 36+
sudo dnf install llvm-libunwind

# Debian 12+
LIBUNWIND_VERSION=$(apt-cache depends llvm | egrep -o 'llvm-[0-9]+' | cut -d- -f2)
sudo apt install libunwind-$LIBUNWIND_VERSION

# Alpine
sudo apk add llvm-libunwind
```

Verify detection: `lib/alys/tools/detect_libunwind.sh`

---

## Setting Up Tracing

```crystal
require "alys"

Alys.setup_from_env
```

Enable tracing via environment variable:

```bash
# Trace to a timestamped file (TIME.alys)
ALYS_TRACING=file crystal myapp.cr

# Trace to a custom file name
ALYS_TRACING=file:myfile.alys ./myapp
```

---

## Converting Traces with `alys_converter`

`.alys` files are in a custom binary format. Convert them using `alys_converter`:

**JSON:**

```bash
bin/alys_converter --symbolize myprog myfile.alys            # → myfile.alys.json
bin/alys_converter --symbolize myprog --indent myfile.alys    # formatted JSON
```

**pprof** (visualize with Google's pprof tool):

```bash
bin/alys_converter --symbolize myprog -f pprof myfile.alys   # → myfile.pb.gz
pprof -http localhost:8080 myfile.pb.gz
```

Four pprof sample indexes available:

- `alloc_objects` — number of objects allocated
- `alloc_space` (default) — bytes allocated over program lifetime
- `inuse_objects` — objects alive at termination
- `inuse_space` (default) — bytes alive at termination

**Folded stacks** (for flamegraph tools):

```bash
bin/alys_converter --symbolize myprog -f folded-stacks myfile.alys  # → myfile.folded
```

**Direct flamegraph** (requires [Inferno](https://github.com/jonhoo/inferno)):

```bash
bin/alys_converter --symbolize myprog -f inferno-flamegraph myfile.alys  # → myfile.svg
bin/alys_converter -f inferno-flamegraph myfile.alys \
  --inferno-opt flamechart --inferno-opt title=test
```

**Important:** `.alys` files are only compatible with an identical `alys_converter` version.

### JSON Schema

The JSON output is an array of event objects:

```json
{
  "id": 29,
  "time": 1.009839517,
  "kind": "alloc",
  "addr": 281471443894272,
  "size": 96,
  "stack": [
    {
      "ip": 4721576,
      "line": 279,
      "file": "/home/ryan/code/alys/src/alys.cr",
      "name": "record_alloc"
    }
  ]
}
```

- `id` — unique ID per allocation (links alloc/realloc/free events)
- `time` — seconds since program start
- `kind` — one of `alloc`, `realloc`, `free`
- `addr` — memory address allocated or freed
- `size` — bytes allocated
- `realloc` events also have `prev_addr` and `prev_size`
- `stack` — array of stack frames with `ip`, `file`, `line`, `name`

Example analysis notebook: [Colab notebook](https://colab.research.google.com/drive/1KdJLRIAno837bc5gNZUU_gLM3OmhD32F?usp=sharing)

---

## Backtrace Configuration

Control backtrace detail via `ALYS_BACKTRACE_TYPE`:

| Value | Backtrace Content | Speed | Notes |
|-------|-------------------|-------|-------|
| `none` | No backtrace | Fastest | Allocation counts only |
| `addr` | Memory addresses only | Fast | Default on Linux; require `--symbolize` with `alys_converter` |
| `name` | Function names (no files/lines) | Moderate | Default on macOS; supports PIE executables |
| `full` | Names, files, line numbers | Very slow | Avoid on release builds |

```bash
ALYS_BACKTRACE_TYPE=none ./myapp
ALYS_BACKTRACE_TYPE=name ./myapp
ALYS_BACKTRACE_TYPE=full ./myapp
```

**Note:** When using `addr` or `name` modes, symbolize backtraces with:

```bash
bin/alys_converter --symbolize ./myapp myfile.alys
```

This requires `llvm-symbolizer` to be installed. Does **not** work on Apple Silicon (M1+) when PIE is enabled.

---

## Performance Notes

### Sampling Intervals

Instead of recording every allocation, sample every N bytes:

```bash
ALYS_SAMPLE_INTERVAL=bytes:N ./myapp
```

### Release Builds Are Much Slower

Release builds omit the frame pointer, making backtrace creation
significantly slower. Debug builds are recommended for profiling.

### Benchmark Results (Lucky website crawl)

| Build   | Tracing | Backtrace Type | Backtrace Limit | Time   |
|---------|---------|----------------|-----------------|--------|
| debug   | N       | N/A            | N/A             | 1.2s   |
| debug   | Y       | none           | N/A             | 2.7s   |
| debug   | Y       | addr           | 5               | 7s     |
| debug   | Y       | addr           | unlimited       | 23s    |
| debug   | Y       | name           | 5               | 9s     |
| debug   | Y       | name           | unlimited       | 33s    |
| debug   | Y       | full           | 5               | 1m8s   |
| debug   | Y       | full           | unlimited       | 8m47s  |
| release | N       | N/A            | N/A             | 0.9s   |
| release | Y       | none           | N/A             | 2.2s   |
| release | Y       | addr           | unlimited       | 1m21s  |
| release | Y       | full           | 5               | 8m4s   |

**Key takeaway:** Use `ALYS_BACKTRACE_TYPE=name` with a backtrace limit
for the best detail-to-speed tradeoff on release builds.

---

## References

- [Alys on sourcehut](https://sr.ht/~refi64/alys/)
- [Alys git repository](https://git.sr.ht/~refi64/alys)
