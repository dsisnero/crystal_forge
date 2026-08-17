# Computation Patterns

Running work concurrently and collecting results: futures, racing, scatter/gather,
parallel reduce, and safe shared state.

Verified against `dsisnero/crystal-concurrency-patterns`.

Patterns: Future/Promise · First Response · Scatter-Gather · Map-Reduce ·
Stateful Fiber (Actor) · Ticker with Cancellation · Mutex-Protected State

---

## Future / Promise

Start work now, collect the result later. A buffered cap-1 channel lets the worker
fiber send its result even if no one is waiting yet — so it never leaks waiting to
hand off.

```crystal
def future(&work : -> Int32) : Channel(Int32)
  ch = Channel(Int32).new(1)        # cap 1: worker can always send, then exit
  spawn { ch.send(work.call) }
  ch
end

f = future { expensive_work }
# ... do other things ...
result = f.receive                  # blocks only if not ready yet
```

Source: `new_patterns_spec.cr` ("Future/Promise"), doc
`timing-futures-rate-limiting.adoc`.

---

## First Response (racing replicas)

Ask N replicas the same question, take the fastest answer, discard the rest. The
channel **must** be buffered to `workers.size` — otherwise the slower fibers block
forever on `send` after the winner is taken, leaking N-1 fibers.

```crystal
def first(workers : Array(Proc(String))) : String
  ch = Channel(String).new(workers.size)   # buffered so losers don't leak
  workers.each { |w| spawn { ch.send(w.call) } }
  ch.receive                                 # fastest wins
end
```

(The upstream Go-port `google3.cr#first` uses an *unbuffered* channel and does leak
the losers — the buffered form here is the one the docs recommend.)

Source: `new_patterns_spec.cr` ("First Response"), doc
`timing-futures-rate-limiting.adoc`.

---

## Scatter-Gather

Fan work out to N tasks, gather as many results as arrive before a **single shared
deadline**. Build the deadline once with an `after` helper (not a per-iteration
`timeout`) so the whole gather shares one clock and returns partial results on
expiry.

```crystal
def after(span : Time::Span) : Channel(Bool)
  ch = Channel(Bool).new
  spawn { sleep span; ch.send(true) }
  ch
end

def scatter_gather(tasks : Array(Proc(String)), deadline : Time::Span) : Array(String)
  results = Channel(String).new(tasks.size)   # buffered: stragglers don't leak
  tasks.each { |t| spawn { results.send(t.call) } }

  collected = [] of String
  timeout_ch = after(deadline)
  tasks.size.times do
    select
    when val = results.receive
      collected << val
    when timeout_ch.receive
      break                                    # deadline hit: return what we have
    end
  end
  collected
end
```

Source: `research_patterns_spec.cr` ("Scatter-Gather"), doc
`state-actors-resilience.adoc`.

---

## Map-Reduce

Map in parallel, reduce sequentially. Each input is transformed in its own fiber;
results funnel through one channel that a `WaitGroup` closes when every mapper is
done, and the reduce loop folds them.

```crystal
require "wait_group"

data = (1..100).to_a
ch = Channel(Int32).new(data.size)
wg = WaitGroup.new(data.size)

data.each do |v|
  spawn { ch.send(v * v); wg.done }    # map (concurrent)
end
spawn { wg.wait; ch.close }

total = 0
while val = ch.receive?                # reduce (sequential)
  total += val
end
```

For CPU-bound maps, run the mappers on a `Fiber::ExecutionContext::Parallel` with
`ctx.spawn` — measured **3.4x** on integer math with 4 threads. See
`references/execution-contexts.md`.

Source: `final_patterns_spec.cr` ("Map-Reduce"), `execution_context_spec.cr`
(parallel variant), doc `production-patterns.adoc`.

---

## Stateful Fiber (Actor)

Give one fiber sole ownership of some state and serialize all access through request
channels. Races are eliminated *by construction* — no locks — which scales better
than juggling several mutexes. Each request carries a reply channel.

```crystal
read_req  = Channel({Int32, Channel(Int32)}).new        # {key, reply}
write_req = Channel({Int32, Int32, Channel(Bool)}).new   # {key, val, reply}

spawn do
  state = {} of Int32 => Int32
  loop do
    select
    when req = read_req.receive
      key, reply = req
      reply.send(state[key]? || 0)
    when req = write_req.receive
      key, val, reply = req
      state[key] = val
      reply.send(true)
    end
  rescue Channel::ClosedError
    break
  end
end

# Write then read:
ack = Channel(Bool).new
write_req.send({1, 42, ack}); ack.receive
reply = Channel(Int32).new
read_req.send({1, reply}); puts reply.receive   # => 42
```

Source: `research_patterns_spec.cr` ("Stateful Fiber (Actor pattern)"), doc
`state-actors-resilience.adoc`. Example: `examples/actor.cr`.

---

## Ticker with Cancellation

Emit a tick on a fixed interval until cancelled. `select` races the `done` channel
against a `timeout` so the ticker stops promptly when asked.

```crystal
def ticker(done : Channel(Bool), interval : Time::Span) : Channel(Int32)
  ticks = Channel(Int32).new
  spawn do
    count = 0
    loop do
      select
      when done.receive?
        break
      when timeout(interval)
        count += 1
        ticks.send(count)
      end
    end
    ticks.close
  end
  ticks
end
```

Source: `research_patterns_spec.cr` ("Ticker"), doc `state-actors-resilience.adoc`.

---

## Mutex-Protected State

When the Actor pattern is overkill and you just need a guarded counter or map, a
`Mutex` is the direct tool. `synchronize` is fiber-safe with Crystal 1.21 runtime
parallel execution contexts. Reach for this for simple shared state; reach for the Actor when the
update logic gets complex enough that multiple mutexes would be error-prone.

```crystal
require "wait_group"

mutex = Mutex.new
counters = {"a" => 0, "b" => 0}

inc = ->(name : String) {
  10_000.times { mutex.synchronize { counters[name] += 1 } }
}

wg = WaitGroup.new(3)
spawn { inc.call("a"); wg.done }
spawn { inc.call("a"); wg.done }
spawn { inc.call("b"); wg.done }
wg.wait
# counters["a"] == 20_000, counters["b"] == 10_000
```

For a single integer, an `Atomic(Int32)` is lighter than a `Mutex`.

Source: `research_patterns_spec.cr` ("Mutex-protected state"), docs
`state-actors-resilience.adoc`, `parallel-programming-crystal.adoc`.
