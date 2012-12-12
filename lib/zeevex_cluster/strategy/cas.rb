require 'zeevex_cluster/coordinator/memcached'
require 'socket'

class ZeevexCluster::Strategy::Cas
  attr_accessor :stale_time, :update_period, :server, :nodename, :cluster_name

  def initialize(options = {})
    @options       = options
    @cluster_name  = options[:cluster_name]
    @nodename      = options[:nodename] || Socket.gethostname
    @stale_time    = options.fetch(:stale_time, 40)
    @update_period = options.fetch(:update_period, 10)
    @hooks         = options[:hooks] || {}
    @state         = :stopped

    reset_state_vars

    @server = options[:coordinator] ||
        ZeevexCluster::Coordinator::Memcached.new(:server     => options[:server],
                                                  :port       => options[:port],
                                                  :expiration => @stale_time)
  end


  def am_i_master?
    !! @my_master_token
  end

  def master_node
    @current_master
  end

  def has_master?
    !! @current_master
  end

  def state
    @state
  end

  def started?
    @state == :started
  end

  def stopped?
    @state == :stopped
  end

  def start
    raise "Already started" if @thread || @state == :started
    @start_time = Time.now
    @state  = :started
    @locked_at = nil
    @thread = Thread.new do
      begin
        spin
      rescue
        puts "rescued from spin: #{$!.inspect}\n#{$!.backtrace.join("\n")}"
      ensure
        puts "spin over"
        @state = :stopped
      end
    end
  end

  def stop
    case @state
      when :stop_requested
      when :stopped
      when :started
        @state = :stop_requested
      else
        raise "Bad state: #{@state}"
    end
    @thread.join
    @thread = nil
    reset_state_vars
  end

  def resign(delay = nil)
    return if !am_i_master?
    server.cas(key) do |val|
      if is_me?(val)
        @resign_until = Time.now + (delay || [@update_period*6, @stale_time].min)
        my_token.merge(:timestamp => Time.now - 2*@stale_time)
      else
        raise ZeevexCluster::Coordinator::DontChange
      end
    end
    failed_lock(my_token, nil)
  end

  protected

  def run_hook(hook_name, *args)
    if @hooks[hook_name]
      @hooks[hook_name].call(self, *args)
    end
  end

  def spin
    puts "spinning"
    @state = :started
    run_hook :started
    while @state == :started
      puts "campaining!"
      campaign
      sleep [@update_period - 1, 1].max if @state == :started
    end
    @state = :stopped
    run_hook :stopped
  end

  def my_token
    {:nodename    => nodename,
     :joined_at   => @start_time,
     :locked_at   => @locked_at,
     :timestamp   => Time.now}
  end

  def key
    cluster_name
  end

  def is_me?(token)
    token && token.is_a?(Hash) && token[:nodename] == nodename
  end

  def got_lock(token)
    unless @locked_at
      @locked_at     = token[:timestamp]
      new_token      = my_token

      token          = new_token
    end
    @my_master_token = token
    if qualifies_for_master?(token)
      if @current_master && is_me?(@current_master)
        run_hook :reelected
      else
        run_hook :election_won
      end
      @current_master  = token
    else
      @current_master  = nil
    end
  end

  def failed_lock(me, winner)
    @my_master_token = nil
    @locked_at       = nil
    @current_master  = qualifies_for_master?(winner) ? winner : nil
    run_hook :election_lost, @current_master
  end

  #
  # Must have held lock for 2 update periods, and been member of the cluster
  # for 3 update periods
  #
  def qualifies_for_master?(token)
    now = Time.now
    ! token_invalid?(token) and
        token[:locked_at] and
        token[:timestamp] > (now - @stale_time) and
        token[:locked_at] <= (now - 2 * @update_period)
  end

  def token_invalid?(token)
    now = Time.now
    !token || !token.is_a?(Hash) || !token[:timestamp] ||
        token[:timestamp] < (now - @stale_time)
  end

  def campaign
    if @resign_until && @resign_until > Time.now
      puts "resigned..."
      return
    end
    @resign_until = nil
    me = my_token
    if server.add(key, me)
      puts "CAS: added!"
      got_lock(me)
      return true
    end

    # we're refreshing cas(old, new)
    res = server.cas(key) do |val|
      if is_me?(val)
        puts "CAS: refreshing!"
        me
      else
        puts "CAS: wasn't me"
        raise ZeevexCluster::Coordinator::DontChange
      end
    end
    puts "res1 was #{res.inspect}"
    if res
      got_lock(me)
      return true
    end

    current = nil
    res = server.cas(key) do |val|
      current = val
      if token_invalid?(val)
        puts "CAS: master invalid, stealing"
        me
      else
        puts "CAS: master valid for #{@stale_time - (Time.now - val[:timestamp])} more seconds" if
          val && val.is_a?(Hash)
        raise ZeevexCluster::Coordinator::DontChange
      end
    end
    puts "res2 was #{res.inspect}"
    if res
      got_lock(me)
      return true
    end

    # didn't get it
    failed_lock(me, current)
    false
  end


  def reset_state_vars
    @resign_until = nil
    @my_master_token = nil
    @current_master = nil
    @state = :stopped
    @thread = nil
  end
end
