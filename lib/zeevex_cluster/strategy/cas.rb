require 'zeevex_cluster/coordinator/memcached'
require 'socket'
require 'logger'

class ZeevexCluster::Strategy::Cas
  include ZeevexCluster::Util

  attr_accessor :stale_time, :update_period, :server, :nodename, :cluster_name

  def initialize(options = {})
    @options       = options
    @cluster_name  = options[:cluster_name]
    @nodename      = options[:nodename] || Socket.gethostname
    @stale_time    = options.fetch(:stale_time, 40)
    @update_period = options.fetch(:update_period, 10)
    @hooks         = options[:hooks] || {}
    @logger        = options[:logger]

    @state         = :stopped

    reset_state_vars

    @server = options[:coordinator] ||
        ZeevexCluster::Coordinator::Memcached.new(:server     => options[:server],
                                                  :port       => options[:port],
                                                  :expiration => @stale_time)
  end


  def am_i_master?
    !! @my_master_token && qualifies_for_master?(@my_master_token)
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
        change_my_status :member
        spin
      rescue
        logger.warn "rescued from spin: #{$!.inspect}\n#{$!.backtrace.join("\n")}"
      ensure
        logger.debug "spin over"
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
    change_my_status :nonmember
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
    logger.debug "<running hook #{hook_name}(#{args.inspect})>"
    if @hooks[hook_name]
      @hooks[hook_name].call(self, *args)
    end
  end

  def spin
    logger.debug "spin started"
    @state = :started
    run_hook :started
    while @state == :started
      campaign
      sleep [@update_period - 1, 1].max if @state == :started
    end
    @state = :stopped
    run_hook :stopped
  end

  def my_token
    now = Time.now
    {:nodename    => nodename,
     :joined_at   => @start_time,
     :locked_at   => @locked_at || now,
     :timestamp   => now}
  end

  def key
    cluster_name
  end

  def is_me?(token)
    token && token.is_a?(Hash) && token[:nodename] == nodename
  end

  def change_my_status(status, attrs = {})
    return if status == @my_cluster_status

    old_status = @my_cluster_status
    @my_cluster_status = status
    run_hook :status_change, status, old_status, attrs
  end

  def got_lock(token)
    unless @locked_at
      @locked_at     = token[:timestamp]
      token          = my_token
      run_hook :election_won
    end
    @my_master_token = token
    if qualifies_for_master?(token)
      change_my_status :master
      if @current_master && is_me?(@current_master)
        run_hook :reelected
      else
        run_hook :became_master
      end
      @current_master  = token
    else
      change_my_status :master_elect
      run_hook :waiting_for_inauguration
      @current_master  = nil
    end
  end

  def failed_lock(me, winner)
    @locked_at       = nil

    @current_master  = qualifies_for_master?(winner) ? winner : nil
    run_hook :election_lost, @current_master

    if @my_master_token
      @my_master_token = nil
      run_hook :lame_duck
    end
  end

  #
  # Must have held lock for 2 update periods, and been member of the cluster
  # for 3 update periods
  #
  def qualifies_for_master?(token)
    now = Time.now
    ! token_invalid?(token) and
        token[:timestamp] > (now - @stale_time) and
        token[:locked_at] <= (now - 2 * @update_period)
  end

  def token_invalid?(token)
    now = Time.now
    !token || !token.is_a?(Hash) || !token[:timestamp] ||
        ! token[:locked_at] || ! token[:nodename] ||
        token[:timestamp] < (now - @stale_time)
  end

  # TODO: make this work
  def steal_election
    false
  end

  def campaign
    if @resign_until && @resign_until > Time.now
      run_hook :staying_resigned
      return
    end
    @resign_until = nil
    me = my_token
    if server.add(key, me)
      logger.debug "CAS: added!"
      got_lock(me)
      return true
    end

    # we're refreshing cas(old, new)
    res = server.cas(key) do |val|
      if is_me?(val)
        me
      else
        logger.debug "CAS: I ain't no fortunate son"
        raise ZeevexCluster::Coordinator::DontChange
      end
    end
    if res
      got_lock(me)
      return true
    end

    current = nil
    hook = nil
    res = server.cas(key) do |val|
      current = val
      if token_invalid?(val)
        logger.info "CAS: master invalid, stealing: #{val.inspect}"
        hook = :deposed_master
        me
      else
        logger.debug "CAS: other master valid for #{@stale_time - (Time.now - val[:timestamp])} more seconds" if
          val && val.is_a?(Hash)
        raise ZeevexCluster::Coordinator::DontChange
      end
    end

    # it's important to run this outside of the CAS block
    run_hook hook if hook

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
    @my_cluster_status = :nonmember
  end
end
