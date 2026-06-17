require "wait_group"

# Pipeline with cancellation: gen -> square -> filter -> consumer
# All stages respect a done channel for clean shutdown.
#
# Build:  crystal run examples/pipeline_cancel.cr

def gen(done : Channel(Bool), nums : Array(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    nums.each do |num|
      select
      when ch.send(num)
      when done.receive?
        break
      end
    end
    ch.close
  end
  ch
end

def square(done : Channel(Bool), input : Channel(Int32)) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    while num = input.receive?
      select
      when ch.send(num * num)
      when done.receive?
        break
      end
    end
    ch.close
  end
  ch
end

def filter_gt(done : Channel(Bool), input : Channel(Int32), threshold : Int32) : Channel(Int32)
  ch = Channel(Int32).new
  spawn do
    while val = input.receive?
      next unless val > threshold
      select
      when ch.send(val)
      when done.receive?
        break
      end
    end
    ch.close
  end
  ch
end

def merge(done : Channel(Bool), channels : Array(Channel(Int32))) : Channel(Int32)
  ch = Channel(Int32).new
  wg = WaitGroup.new(channels.size)
  channels.each do |src|
    spawn do
      while val = src.receive?
        select
        when ch.send(val)
        when done.receive?
          break
        end
      end
      wg.done
    end
  end
  spawn do
    wg.wait
    ch.close
  end
  ch
end

done = Channel(Bool).new
input = gen(done, (1..20).to_a)

# Fan out: two square stages reading from same input
c1 = square(done, input)
c2 = square(done, input)

# Fan in: merge, then filter
merged = merge(done, [c1, c2])
filtered = filter_gt(done, merged, 50)

# Consumer: take only first 5 results, then cancel
count = 0
while val = filtered.receive?
  puts "Result #{count + 1}: #{val}"
  count += 1
  if count >= 5
    puts "Got enough results, cancelling pipeline..."
    done.close
    break
  end
end

# Drain any remaining values (pipeline is shutting down)
while filtered.receive?
end

puts "Done. Processed #{count} results with no fiber leaks."
