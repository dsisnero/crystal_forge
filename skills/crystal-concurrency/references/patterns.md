# Crystal Concurrency Patterns

31 patterns, all verified with specs. Grouped by category.

## Basic

### Generator

```crystal
def generator : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    i = 0
    loop { ch.send(i); i += 1 }
  end
  ch
end
```

### Fan-In (merge N channels into 1)

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

### Fan-Out (split 1 channel to N readers)

```crystal
def fan_out(input : Channel(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    while val = input.receive?
      ch.send(val)
    end
    ch.close
  end
  ch
end
```

### Pipeline (chain stages)

```crystal
def square(input : Channel(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    while val = input.receive?
      ch.send(val * val)
    end
    ch.close
  end
  ch
end

pipeline = half(square(filter_even(gen([0, 1, 2, 3, 4]))))
```

### Confinement (one fiber owns the data)

```crystal
def producer : Channel(Int32)
  ch = Channel(Int32).new(5)
  spawn do
    5.times { |i| ch.send(i) }
    ch.close
  end
  ch
end
```

### For-Select Loop (long-lived fiber with done)

```crystal
spawn do
  loop do
    select
    when done.receive?
      break
    else
    end
    do_work
    sleep 10.milliseconds
  end
end
```

## Coordination

### Worker Pool

```crystal
require "wait_group"

def worker(id, jobs : Channel(Int32), results : Channel(Int32))
  while job = jobs.receive?
    results.send(job * 2)
  end
end

wg = WaitGroup.new(num_workers)
num_workers.times do |id|
  spawn { worker(id, jobs, results); wg.done }
end
spawn { wg.wait; results.close }
```

### Bounded Parallelism

```crystal
wg = WaitGroup.new(20)
20.times do
  spawn do
    digester(done, paths, results)
    wg.done
  end
end
spawn { wg.wait; results.close }
```

### Queuing (semaphore)

```crystal
sem = Channel(Bool).new(limit)
work_count.times do |i|
  sem.send(true)   # acquire slot
  spawn do
    do_work(i)
    sem.receive     # release slot
  end
end
```

### Daisy Chain

```crystal
n = 1000
leftmost = Channel(Int32).new
left = leftmost
n.times do
  right = Channel(Int32).new
  spawn { left.send(1 + right.receive) }
  left = right
end
spawn { left.send(1) }
leftmost.receive  # => 1001
```

## Cancellation

### Done Channel (broadcast)

```crystal
done = Channel(Bool).new
# In workers:
select
when done.receive?
  break
when ch.send(val)
end
# Cancel all:
done.close
```

### Quit Signal (request-reply)

```crystal
quit = Channel(String).new
# In worker:
select
when ch.send(val)
when quit.receive
  quit.send("See you!")
  break
end
# Caller:
quit.send("Bye")
farewell = quit.receive
```

### Or-Channel (merge cancellation signals)

```crystal
channels.each do |ch|
  spawn do
    ch.receive?
    merged.close rescue nil
  end
end
```

### Or-Done (wrap channel with done)

```crystal
def or_done(done : Channel(Bool), input : Channel(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    loop do
      select
      when done.receive?
        break
      when val = input.receive
        ch.send(val)
      end
    rescue Channel::ClosedError
      break
    end
    ch.close
  end
  ch
end
```

### Errgroup (cancel-on-first-error)

```crystal
tasks.each do |task|
  spawn do
    begin
      task.call(done)
      errc.send nil
    rescue ex
      errc.send ex
      done.close rescue nil
    ensure
      wg.done
    end
  end
end
```

### Graceful Shutdown

```crystal
done.close       # signal stop
jobs.close       # stop accepting
wg.wait          # drain active work
```

## Data Flow

### Tee Channel (duplicate to 2 outputs)

```crystal
# Crystal lacks nil-channel-in-select, use boolean flags:
while val = input.receive?
  sent1 = sent2 = false
  2.times do
    if !sent1 && !sent2
      select
      when out1.send(val); sent1 = true
      when out2.send(val); sent2 = true
      end
    elsif !sent1
      out1.send(val); sent1 = true
    else
      out2.send(val); sent2 = true
    end
  end
end
```

### Bridge Channel (flatten channel-of-channels)

```crystal
spawn do
  while stream = chan_stream.receive?
    while val = stream.receive?
      out.send(val)
    end
  end
  out.close
end
```

### Ring Buffer (keep last N)

```crystal
# Crystal select/else has quirks with buffered channels.
# Use internal Deque instead:
while val = in_ch.receive?
  buffer.shift if buffer.size >= capacity
  buffer.push(val)
end
buffer.each { |v| out_ch.send(v) }
out_ch.close
```

### Broadcaster (one-to-many)

```crystal
while msg = input.receive?
  subscribers.each(&.send(msg))
end
subscribers.each(&.close)
```

### Pub/Sub (topic-based)

```crystal
subs = {} of String => Array(Channel(String))
mu = Mutex.new

subscribe = ->(topic : String) {
  ch = Channel(String).new(10)
  mu.synchronize { (subs[topic] ||= [] of Channel(String)) << ch }
  ch
}

publish = ->(topic : String, msg : String) {
  mu.synchronize { subs[topic]?.try(&.each(&.send(msg))) }
}
```

## Resilience

### Rate Limiting

```crystal
while requests.receive?
  sleep rate
  process_request
end
```

### Bursty Rate Limiting

```crystal
limiter = Channel(Bool).new(burst_limit)
burst_limit.times { limiter.send(true) }
spawn do
  loop do
    sleep rate
    select
    when limiter.send(true)
    else
    end
  end
end
```

### Retry with Backoff

```crystal
max_retries.times do |attempt|
  begin
    result = yield
    break
  rescue ex
    sleep base_delay * (2 ** attempt)
  end
end
```

### Circuit Breaker

States: closed → (N failures) → open → (cooldown) → half-open → (success) → closed

```crystal
if state.get == 1  # open
  elapsed = Time.utc.to_unix_ms - last_failure.get
  state.set(2) if elapsed >= cooldown  # half-open
  raise "circuit open" unless state.get == 2
end
begin
  result = work.call
  failures.set(0); state.set(0)  # closed
rescue ex
  count = failures.add(1) + 1
  state.set(1) if count >= max_failures  # open
  raise ex
end
```

### Backpressure

```crystal
ch = Channel(Int32).new(2)  # buffer IS the backpressure
# Producer blocks when buffer full
# Consumer reads at its own pace
```

### Batch/Debounce

```crystal
loop do
  select
  when val = input.receive
    batch << val
    if batch.size >= max_batch
      flush(batch); batch.clear
    end
  when timeout(window)
    flush(batch); batch.clear unless batch.empty?
  end
rescue Channel::ClosedError
  flush(batch) unless batch.empty?
  break
end
```

## Computation

### Future/Promise

```crystal
ch = Channel(Int32).new(1)
spawn { ch.send(expensive_work) }
# ... do other work ...
result = ch.receive  # blocks only if not ready
```

### First Response (racing replicas)

```crystal
ch = Channel(String).new(workers.size)  # buffered!
workers.each { |w| spawn { ch.send(w.call) } }
ch.receive  # fastest wins, losers absorbed by buffer
```

### Scatter-Gather

```crystal
tasks.each { |t| spawn { results.send(t.call) } }
tasks.size.times do
  select
  when val = results.receive
    collected << val
  when timeout_ch.receive
    break  # deadline: return partial results
  end
end
```

### Map-Reduce

```crystal
# Map: parallel
data.each { |v| spawn { ch.send(transform(v)); wg.done } }
spawn { wg.wait; ch.close }
# Reduce: sequential
while val = ch.receive?
  total += val
end
```

### Stateful Fiber (Actor)

```crystal
spawn do
  state = {} of Int32 => Int32
  loop do
    select
    when req = read_ch.receive
      key, resp = req
      resp.send(state[key]? || 0)
    when req = write_ch.receive
      key, val, resp = req
      state[key] = val
      resp.send(true)
    end
  rescue Channel::ClosedError
    break
  end
end
```

### Ticker with Cancellation

```crystal
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
```

### Mutex-Protected State

```crystal
mutex = Mutex.new
counters = {"a" => 0}
mutex.synchronize { counters["a"] += 1 }
```
