# Pub/Sub: topic-based message routing with dynamic subscribers.
#
# Build:  crystal run examples/pubsub.cr

class PubSub
  @subs : Hash(String, Array(Channel(String)))
  @mu : Mutex

  def initialize
    @subs = {} of String => Array(Channel(String))
    @mu = Mutex.new
  end

  def subscribe(topic : String) : Channel(String)
    ch = Channel(String).new(10)
    @mu.synchronize do
      (@subs[topic] ||= [] of Channel(String)) << ch
    end
    ch
  end

  def unsubscribe(topic : String, ch : Channel(String))
    @mu.synchronize do
      if list = @subs[topic]?
        list.delete(ch)
      end
    end
    ch.close
  end

  def publish(topic : String, msg : String)
    @mu.synchronize do
      if channels = @subs[topic]?
        channels.each(&.send(msg))
      end
    end
  end

  def close_all
    @mu.synchronize do
      @subs.each_value do |channels|
        channels.each(&.close)
      end
      @subs.clear
    end
  end
end

bus = PubSub.new

tech = bus.subscribe("tech")
sports = bus.subscribe("sports")
tech2 = bus.subscribe("tech")

# Consumers
spawn do
  while msg = tech.receive?
    puts "[tech-1]  #{msg}"
  end
  puts "[tech-1]  unsubscribed"
end

spawn do
  while msg = tech2.receive?
    puts "[tech-2]  #{msg}"
  end
  puts "[tech-2]  unsubscribed"
end

spawn do
  while msg = sports.receive?
    puts "[sports]  #{msg}"
  end
  puts "[sports]  unsubscribed"
end

# Producer
bus.publish("tech", "Crystal 2.0 released")
bus.publish("sports", "Team wins championship")
bus.publish("tech", "New ExecutionContext landed")
bus.publish("sports", "Record-breaking marathon")

sleep 50.milliseconds

# Unsubscribe one tech consumer
bus.unsubscribe("tech", tech2)
bus.publish("tech", "Only tech-1 sees this")

sleep 50.milliseconds

bus.close_all
sleep 50.milliseconds

puts "Done."
