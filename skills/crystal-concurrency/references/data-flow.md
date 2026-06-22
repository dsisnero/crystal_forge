# Data Flow Patterns

Routing values between channels: duplicating, flattening, fanning out to many, and
topic routing.

Verified against `dsisnero/crystal-concurrency-patterns`.

Patterns: Tee Channel · Bridge Channel · Ring Buffer · Broadcaster · Pub/Sub ·
Subscription

---

## Tee Channel (duplicate to two outputs)

Send every input value to **both** outputs. Go disables an already-sent `select`
case by nilling its channel; Crystal cannot express a nil channel in `select`, so we
track which output still needs the value with boolean flags.

```crystal
def tee(input : Channel(Int32)) : {Channel(Int32), Channel(Int32)}
  out1 = Channel(Int32).new
  out2 = Channel(Int32).new
  spawn do
    while val = input.receive?
      sent1 = sent2 = false
      2.times do
        if !sent1 && !sent2
          select                  # whichever is ready first
          when out1.send(val) then sent1 = true
          when out2.send(val) then sent2 = true
          end
        elsif !sent1
          out1.send(val); sent1 = true
        else
          out2.send(val); sent2 = true
        end
      end
    end
    out1.close
    out2.close
  end
  {out1, out2}
end
```

Source: `opcito_patterns_spec.cr` ("10. Tee Channel"), doc
`broadcasting-and-cancellation.adoc`.

---

## Bridge Channel (flatten a channel of channels)

Consume a stream whose elements are themselves channels, presenting their values as
one flat stream. Useful when each unit of work produces its own result channel.

```crystal
def bridge(input : Channel(Channel(Int32))) : Channel(Int32)
  out = Channel(Int32).new
  spawn do
    while stream = input.receive?
      while val = stream.receive?
        out.send(val)
      end
    end
    out.close
  end
  out
end
```

Source: `opcito_patterns_spec.cr` ("11. Bridge Channel").

---

## Ring Buffer (keep last N, drop oldest)

A bounded buffer that overwrites the oldest value when full — for "latest wins"
telemetry where you'd rather drop stale data than block the producer. Backed by an
internal `Deque`, **not** `select/else`: Crystal's `select/else` over a buffered
channel can occasionally let one extra item through (an off-by-one), so the Deque is
the reliable form.

```crystal
class RingBuffer
  @buffer = Deque(Int32).new

  def initialize(@in_ch : Channel(Int32), @out_ch : Channel(Int32), @capacity : Int32 = 4)
  end

  def run
    while val = @in_ch.receive?
      @buffer.shift if @buffer.size >= @capacity   # drop oldest
      @buffer.push(val)
    end
    while !@buffer.empty?
      @out_ch.send(@buffer.shift)
    end
    @out_ch.close
  rescue Channel::ClosedError
  end
end
```

Source: `src/concurrency_patterns/ring_buffer_channel.cr`, spec
`ring_buffer_channel_spec.cr`. The `select/else` quirk is documented in
`references/channel-rules.md`.

---

## Broadcaster (one-to-many)

Every subscriber receives **every** message (contrast with Fan-Out, where each value
goes to exactly one reader). Closing the input closes all subscriber channels.

```crystal
def broadcast(input : Channel(String), subscribers : Array(Channel(String)))
  spawn do
    while msg = input.receive?
      subscribers.each(&.send(msg))
    end
    subscribers.each(&.close)
  end
end
```

A slow subscriber blocks the broadcaster — give subscriber channels a buffer, or use
Pub/Sub below for dynamic membership.

Source: `additional_patterns_spec.cr` ("Broadcaster"), doc
`broadcasting-and-cancellation.adoc`.

---

## Pub/Sub (topic-based)

Dynamic broadcaster: subscribers come and go, keyed by topic. A `Mutex` guards the
subscriber map (it is shared mutable state); subscriber channels are buffered so a
slow consumer can't block `publish`.

```crystal
subs = {} of String => Array(Channel(String))
mu = Mutex.new

subscribe = ->(topic : String) {
  ch = Channel(String).new(10)            # buffered: publisher never blocks here
  mu.synchronize { (subs[topic] ||= [] of Channel(String)) << ch }
  ch
}

publish = ->(topic : String, msg : String) {
  mu.synchronize { subs[topic]?.try(&.each(&.send(msg))) }
}
```

Source: `final_patterns_spec.cr` ("Pub/Sub"), doc `production-patterns.adoc`.
Example: `examples/pubsub.cr` (adds unsubscribe + clean shutdown).

---

## Subscription (aggregator with the nil-channel workaround)

The Go "advanced concurrency" RSS aggregator: a single fiber owns pending items,
periodically fires an async fetch, and serves the next item to the consumer — all in
one `select`. In Go, cases are enabled/disabled by nilling channels (e.g. don't offer
`updates <- first` when `pending` is empty). **Crystal cannot nil a channel inside
`select`**, so the single Go `select` becomes several `select` blocks chosen by an
`if/else` on the current state:

```crystal
# State: pending items, an optional in-flight fetch, an optional fetch trigger.
if start_fetch && fetch_done.nil?
  select                                  # idle: may start a fetch or serve an item
  when start_fetch.receive then fetch_done = start_async_fetch
  when errc = closing.receive then handle_close(errc)
  when updates.send(first) then pending.shift
  end
elsif fetch_done
  select                                  # fetch in flight: may finish or serve
  when result = fetch_done.receive then fetch_done = nil; apply(result)
  when errc = closing.receive then handle_close(errc)
  when updates.send(first) then pending.shift
  end
else
  select                                  # nothing to fetch: only close or serve
  when errc = closing.receive then handle_close(errc)
  when updates.send(first) then pending.shift
  end
end
```

Each branch is the Go `select` with the currently-disabled (nil) cases physically
removed. The full implementation also dedups by guid (`Set(String)`) and closes with
a reply channel (`Channel(Channel(Exception?))`).

Source: `src/concurrency_patterns/subscription.cr` (example only — no spec); the
nil-channel rationale is in `references/channel-rules.md` and doc
`crystal-channel-behavior.adoc`. Example: `examples/14_subscription.cr` (upstream).
