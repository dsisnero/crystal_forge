# Basic Patterns

Building blocks: turning fibers + channels into streams. Everything here is the
foundation the other categories compose.

All code is ported from and verified against the upstream
`dsisnero/crystal-concurrency-patterns` repo (Crystal port of lotusirous'
Go Concurrency Patterns). Each pattern cites the spec or source that exercises it.
"spec" = a characterization test asserts the behavior; "example only" = there is a
runnable program but no assertion.

Patterns: Generator · Fan-In · Fan-Out · Pipeline · Confinement · For-Select Loop ·
Repeat/Take Generators · Error-Handling Channel

---

## Generator

A function that owns a fiber and returns a channel — the channel *is* the stream.
The canonical way to hand a producer to a caller without exposing the fiber.

```crystal
def generator(msg : String) : Channel(String)
  ch = Channel(String).new
  spawn do
    10.times do |i|
      ch.send("#{msg} #{i}")
      sleep rand(100).milliseconds
    end
    ch.close
  end
  ch
end

ch = generator("tick")
while val = ch.receive?   # drains until the producer closes
  puts val
end
```

Source: `src/concurrency_patterns/generator.cr`, spec `generator_spec.cr`.

---

## Fan-In (merge N channels into 1)

Many producers, one consumer. The robust form uses a `WaitGroup` so the merged
channel closes exactly when every input has drained — no early close, no leak.

```crystal
require "wait_group"

def fan_in(inputs : Array(Channel(Int32))) : Channel(Int32)
  ch = Channel(Int32).new
  wg = WaitGroup.new(inputs.size)
  inputs.each do |input|
    spawn do
      while val = input.receive?
        ch.send(val)
      end
      wg.done
    end
  end
  spawn { wg.wait; ch.close }
  ch
end
```

Output order across inputs is **not** guaranteed. With runtime parallel workers, this
`WaitGroup` + `receive?` form is required — a bare `select when ch.receive` over
closeable inputs raises `ClosedError` on real threads.

Source: `fan_in_spec.cr`, `opcito_patterns_spec.cr` ("8. Fan-Out, Fan-In"),
doc `pipelines-and-cancellation.adoc`.

---

## Fan-Out (split 1 channel to N readers)

One source, many workers. Each value goes to exactly **one** reader (this is the
difference from a broadcaster/pub-sub, where every subscriber gets every value).
Spawn N readers on the same input channel, then merge their outputs back.

```crystal
require "wait_group"

def fan_out(input : Channel(Int32)) : Channel(Int32)
  out = Channel(Int32).new
  spawn do
    while val = input.receive?
      out.send(val)
    end
    out.close
  end
  out
end

outs = Array.new(4) { fan_out(input) }      # 4 competing readers

merged = Channel(Int32).new(8)
wg = WaitGroup.new(outs.size)
outs.each do |o|
  spawn do
    while val = o.receive?
      merged.send(val)
    end
    wg.done
  end
end
spawn { wg.wait; merged.close }
```

Source: `additional_patterns_spec.cr` ("Fan-Out"),
`opcito_patterns_spec.cr` ("8. Fan-Out, Fan-In").

---

## Pipeline (chain stages)

A series of stages connected by channels; each stage receives upstream, transforms,
sends downstream, and **closes its outbound channel when its inbound channel
closes**. Because `sq` has the same in/out type, it composes any number of times.

```crystal
def gen(nums : Array(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    nums.each { |n| ch.send(n) }
    ch.close
  end
  ch
end

def sq(input : Channel(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    while n = input.receive?
      ch.send(n * n)
    end
    ch.close
  end
  ch
end

pipeline = sq(sq(gen([2, 3])))   # => 16, 81
while val = pipeline.receive?
  puts val
end
```

To stop a pipeline early without leaking the upstream senders, thread a `done`
channel through every stage — see Cancellation → Done Channel, and the full
`examples/pipeline_cancel.cr`.

Source: `opcito_patterns_spec.cr` ("6. Pipelines"), `additional_patterns_spec.cr`
("Pipeline with filter stage"), doc `pipelines-and-cancellation.adoc`.
Example: `examples/pipeline_cancel.cr`.

---

## Confinement (one fiber owns the data)

Avoid locks by giving exactly one fiber write access to a value, then publishing
results through a channel. The simplest safe-by-construction pattern.

```crystal
def producer : Channel(Int32)
  ch = Channel(Int32).new(5)   # buffered: producer never blocks here
  spawn do
    5.times { |i| ch.send(i) }
    ch.close
  end
  ch
end

ch = producer
results = [] of Int32
while val = ch.receive?
  results << val
end
```

Source: `opcito_patterns_spec.cr` ("1. Confinement").

---

## For-Select Loop (long-lived fiber with done)

A worker fiber that does work each tick but checks a `done` channel without
blocking — `select ... else` is the non-blocking poll (Go's `select { default: }`).
Crystal fibers are **not** garbage collected, so a long-lived fiber must be given a
way to exit or it leaks.

```crystal
done = Channel(Bool).new

spawn do
  loop do
    select
    when done.receive?
      break
    else
      # non-blocking: fall through and keep working
    end
    do_work
    sleep 10.milliseconds
  end
end

# later, from anywhere:
done.close   # broadcast: wakes the loop's done.receive?
```

Source: `opcito_patterns_spec.cr` ("2. For-Select Loop").

---

## Repeat / Take Generators

Composable generator idiom from the Go pipelines talk: an infinite `repeat`
generator that a `take` stage bounds. `done` lets both stages exit cleanly.

```crystal
def repeat(done : Channel(Bool), *values : Int32) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    stop = false
    until stop
      values.each do |v|
        select
        when ch.send(v)
        when done.receive?
          stop = true
          break               # leave .each; the `until` then exits
        end
      end
    end
    ch.close
  end
  ch
end

def take(done : Channel(Bool), input : Channel(Int32), n : Int32) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    n.times do
      select
      when v = input.receive
        ch.send(v)
      when done.receive?
        break
      end
    end
    ch.close
  end
  ch
end

done = Channel(Bool).new
src = take(done, repeat(done, 1, 2), 5)
result = [] of Int32
while v = src.receive?
  result << v        # => [1, 2, 1, 2, 1]
end
done.close
```

Source: `opcito_patterns_spec.cr` ("7. Generators").

---

## Error-Handling Channel

When a stage can fail, don't crash the fiber — send a result that carries either a
value or an error, and let the consumer decide. Keeps a pipeline composable in the
presence of failures.

```crystal
record Result(T), value : T?, err : Exception?

def worker(inputs : Channel(Int32)) : Channel(Result(Int32))
  out = Channel(Result(Int32)).new
  spawn do
    while n = inputs.receive?
      begin
        raise "negative" if n < 0
        out.send(Result(Int32).new(n * 2, nil))
      rescue ex
        out.send(Result(Int32).new(nil, ex))
      end
    end
    out.close
  end
  out
end

while r = worker(inputs).receive?
  if e = r.err
    STDERR.puts "failed: #{e.message}"
  else
    puts r.value
  end
end
```

Source: `opcito_patterns_spec.cr` ("5. Error Handling").
