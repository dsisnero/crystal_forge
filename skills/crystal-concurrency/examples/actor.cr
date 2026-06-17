require "wait_group"

# Actor pattern: one fiber owns state, others communicate via channels.
# No mutex needed — the channel serializes all access.
#
# Build:  crystal run examples/actor.cr
#
# This example creates a key-value store actor, then reads/writes from
# multiple concurrent fibers.

alias ReadReq = {Int32, Channel(Int32)}
alias WriteReq = {Int32, Int32, Channel(Bool)}

def start_actor : {Channel(ReadReq), Channel(WriteReq)}
  read_ch = Channel(ReadReq).new
  write_ch = Channel(WriteReq).new

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

  {read_ch, write_ch}
end

read_ch, write_ch = start_actor

wg = WaitGroup.new

# 10 writers, each writing their own key
10.times do |writer_id|
  wg.add(1)
  spawn do
    resp = Channel(Bool).new
    100.times do |i|
      write_ch.send({writer_id, i, resp})
      resp.receive
    end
    wg.done
  end
end

# 5 readers, each reading random keys
5.times do |reader_id|
  wg.add(1)
  spawn do
    resp = Channel(Int32).new
    20.times do
      key = rand(10)
      read_ch.send({key, resp})
      val = resp.receive
      puts "Reader #{reader_id}: key=#{key} val=#{val}"
    end
    wg.done
  end
end

wg.wait

# Read final state
resp = Channel(Int32).new
10.times do |key|
  read_ch.send({key, resp})
  puts "Final state[#{key}] = #{resp.receive}"
end

read_ch.close
write_ch.close
