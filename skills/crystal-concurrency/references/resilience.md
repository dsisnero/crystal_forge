# Resilience Patterns

Surviving load and failure: pacing requests, retrying, failing fast, and absorbing
bursts.

Verified against `dsisnero/crystal-concurrency-patterns`.

Patterns: Rate Limiting · Bursty Rate Limiting · Retry with Backoff ·
Circuit Breaker · Backpressure · Batch/Debounce

---

## Rate Limiting (steady)

Enforce a minimum interval between operations by sleeping a fixed `rate` before each
one. The simplest limiter — one operation every `rate`.

```crystal
rate = 50.milliseconds
while requests.receive?
  sleep rate
  process_request
end
```

Source: `new_patterns_spec.cr` ("Rate Limiting"), doc
`timing-futures-rate-limiting.adoc`.

---

## Bursty Rate Limiting (token bucket)

Allow short bursts up to `burst_limit`, refilling one token every `rate`. A
buffered `Channel(Bool)` is the bucket; a refill fiber tops it up with `select/else`
so it never blocks when the bucket is already full (Go's `select { default: }`).

```crystal
burst_limit = 3
rate = 50.milliseconds
limiter = Channel(Bool).new(burst_limit)
burst_limit.times { limiter.send(true) }     # start full

spawn do
  loop do
    sleep rate
    select
    when limiter.send(true)                   # add a token
    else                                       # bucket full: drop the token
    end
  end
end

# Before each request, take a token (bursts of up to 3 go through immediately):
limiter.receive
do_request
```

Source: `new_patterns_spec.cr` ("Bursty Rate Limiting"), doc
`timing-futures-rate-limiting.adoc`.

---

## Retry with Backoff

Retry a failing operation with exponentially growing delays: `base`, `2*base`,
`4*base`, … Stop on success or after `max_attempts`.

```crystal
def retry_with_backoff(max_attempts : Int32, base_delay : Time::Span, &block : -> String) : String?
  result : String? = nil
  max_attempts.times do |attempt|
    begin
      return block.call
    rescue ex
      sleep base_delay * (2 ** attempt)
    end
  end
  result
end
```

In production add jitter (`base_delay * (2 ** attempt) * rand`) to avoid a
thundering herd of clients retrying in lockstep.

Source: `research_patterns_spec.cr` ("Retry with Backoff"), doc
`state-actors-resilience.adoc`.

---

## Circuit Breaker

Stop hammering a failing dependency: after `max_failures` consecutive failures the
breaker **opens** and fails fast; after a `cooldown` it goes **half-open** to test
one call; a success **closes** it again. State is held in `Atomic`s so it is safe to
share across fibers.
States: `0 = closed`, `1 = open`, `2 = half-open`.

```crystal
state       = Atomic(Int32).new(0)
failures    = Atomic(Int32).new(0)
last_failure = Atomic(Int64).new(0_i64)
max_failures = 3
cooldown     = 100.milliseconds

call = ->(work : Proc(String)) {
  if state.get == 1                                   # open
    elapsed = Time.utc.to_unix_ms - last_failure.get
    if elapsed >= cooldown.total_milliseconds
      state.set(2)                                    # half-open: allow one probe
    else
      raise "circuit open"
    end
  end

  begin
    result = work.call
    failures.set(0)
    state.set(0)                                      # success closes it
    result
  rescue ex
    last_failure.set(Time.utc.to_unix_ms)
    state.set(1) if failures.add(1) + 1 >= max_failures
    raise ex
  end
}
```

Source: `final_patterns_spec.cr` ("Circuit Breaker"), doc `production-patterns.adoc`.

---

## Backpressure

The cheapest flow control: a bounded channel **is** the backpressure. When the
buffer fills, the producer blocks on `send` until the consumer catches up — no
explicit signaling needed.

```crystal
ch = Channel(Int32).new(2)        # buffer of 2 is the backpressure window
spawn do
  10.times { |i| ch.send(i) }     # blocks once 2 are queued and unconsumed
  ch.close
end
# Consumer reads at its own pace; producer can never get more than ~2 ahead.
while val = ch.receive?
  process(val)
end
```

When you'd rather drop than block, use the Ring Buffer (Data Flow) instead.

Source: `final_patterns_spec.cr` ("Backpressure"), doc `production-patterns.adoc`.

---

## Batch / Debounce

Group items into batches, flushing when the batch fills **or** when a quiet window
elapses. The size-flush form maximizes throughput; the timeout-flush form bounds
latency (debounce).

```crystal
# Flush on size:
spawn do
  batch = [] of Int32
  while val = input.receive?
    batch << val
    if batch.size >= 3
      batches.send(batch.dup); batch.clear
    end
  end
  batches.send(batch.dup) unless batch.empty?    # flush remainder
  batches.close
end

# Flush on a quiet window (debounce) — select against a timeout:
spawn do
  batch = [] of Int32
  loop do
    select
    when val = input.receive
      batch << val
    when timeout(30.milliseconds)
      unless batch.empty?
        flushed.send(batch.dup); batch.clear
      end
    end
  rescue Channel::ClosedError
    flushed.send(batch.dup) unless batch.empty?
    break
  end
end
```

Source: `final_patterns_spec.cr` ("Batch/Debounce"), doc `production-patterns.adoc`.
