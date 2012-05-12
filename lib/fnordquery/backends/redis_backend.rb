class FnordQuery::RedisBackend

  require "em-hiredis"

  def initialize(opts={})
    @opts = opts
    @prefix = "fnordquery"

    @channel   = EM::Channel.new
    @sub_redis = EM::Hiredis.connect() # FIXPAUL
    @redis     = EM::Hiredis.connect() # FIXPAUL

    redis_subscribe
  end

  def subscribe(query, &block)
    if query.until == :stream
      @channel.subscribe do |event|
        block.call(event) if query.matches?(event)
      end
    end
    if query.since != :now
      q_until = query.until.is_a?(Symbol)? Time.now.to_i : query.until 
      puts "zrangebyscore #{@prefix} #{query.since} #{q_until}"
      @redis.zrangebyscore(@prefix, query.since, q_until) do |res|
        res.each do |event|
          block.call(event) if query.matches?(event)
        end
        if query.until != :stream
          on_finish
        end
      end
    end
  end

  def on_finish(&block)    
    return @on_finish = block if block_given?
    @on_finish.call() if @on_finish
  end

  def publish(message, opts={})
    if message.is_a?(String)
      begin
        message = JSON.parse(message)
      rescue
        puts "redisbackend: published invalid json"
        return false
      end
    end

    message["_time"] ||= Time.now.to_i
    message["_eid"]  ||= rand(8**64).to_s(36)
    
    @redis.publish(@prefix, message.to_json)
    @redis.zadd(@prefix, message["_time"], message.to_json)
  end

private

  def redis_subscribe
    @sub_redis.subscribe(@prefix)
    @sub_redis.on(:message) do |chan, raw|
      begin
        message = JSON.parse(raw)
      rescue
        puts "redisbackend: received invalid json"
      else
        @channel.push(message)
      end
    end
  end

end