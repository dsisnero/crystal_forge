require "wait_group"

# Errgroup: run N tasks, cancel all when the first one fails.
# Returns the first error (or nil if all succeed).
#
# Build:  crystal run examples/errgroup.cr

def errgroup(tasks : Array(Proc(Channel(Bool), Nil))) : Exception?
  done = Channel(Bool).new
  errc = Channel(Exception?).new(tasks.size)
  wg = WaitGroup.new(tasks.size)

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

  spawn do
    wg.wait
    errc.close
  end

  first_err : Exception? = nil
  while err = errc.receive?
    first_err = err if err && first_err.nil?
  end
  first_err
end

# --- Example: 3 tasks, task 2 fails after 50ms ---

tasks = [
  ->(done_ch : Channel(Bool)) {
    5.times do |i|
      select
      when done_ch.receive?
        puts "Task 1: cancelled at step #{i}"
        return
      when timeout(30.milliseconds)
        puts "Task 1: step #{i}"
      end
    end
    puts "Task 1: completed"
    nil
  },
  ->(_done_ch : Channel(Bool)) {
    sleep 50.milliseconds
    puts "Task 2: raising error"
    raise "task 2 failed: database connection refused"
    nil
  },
  ->(done_ch : Channel(Bool)) {
    10.times do |i|
      select
      when done_ch.receive?
        puts "Task 3: cancelled at step #{i}"
        return
      when timeout(20.milliseconds)
        puts "Task 3: step #{i}"
      end
    end
    puts "Task 3: completed"
    nil
  },
] of Proc(Channel(Bool), Nil)

puts "Running errgroup..."
err = errgroup(tasks)

if err
  puts "\nFirst error: #{err.message}"
else
  puts "\nAll tasks succeeded"
end
