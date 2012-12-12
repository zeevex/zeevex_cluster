require 'zeevex_cluster/coordinator/memcached'
require 'socket'
require 'logger'

class ZeevexCluster::Strategy::Cas
  include ZeevexCluster::Util
  include ZeevexCluster::Hooks

  attr_accessor :stale_time, :update_period, :server, :nodename, :cluster_name

  SUSPECT_MISSED_UPDATE_COUNT = 3
  INAUGURATION_UPDATE_DELAY   = 2

  def initialize(options = {})
    @options       = options
    @cluster_name  = options[:cluster_name]
    @nodename      = options[:nodename] || Socket.gethostname
    @stale_time    = options.fetch(:stale_time, 40)
    @update_period = options.fetch(:update_period, 10)
    @hooks         = {}
    @logger        = options[:logger]

    @state         = :stopped

    reset_state_vars

    @server = options[:coordinator] ||
        ZeevexCluster::Coordinator::Memcached.new(:server     => options[:server],
                                                  :port       => options[:port],
                                                  :expiration => @stale_time)


    if options[:hooks]
      add_hooks options[:hooks]
    end
  end


  def am_i_master?
    @my_cluster_status == :master
  end

  def master_node
    @current_master
  end

  def master_nodename
    @current_master && @current_master[:nodename]
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

  class StopException < StandardError; end

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
        @thread.raise(StopException.new 'stop')
      else
        raise "Bad state: #{@state}"
    end
    @thread.join
    @thread = nil
    change_my_status :nonmember
    reset_state_vars
  end

  def resign(delay = nil)
    # unresign
    if delay == 0
      @resign_until = nil
      campaign
    else
      @resign_until = Time.now + (delay || [@update_period*6, @stale_time].min)
      current = nil
      server.cas(key) do |val|
        current = val
        if is_me?(val)
          my_token.merge(:timestamp => Time.now - 2*@stale_time)
        else
          raise ZeevexCluster::Coordinator::DontChange
        end
      end
      failed_lock(my_token, current)
    end
  rescue ZeevexCluster::Coordinator::ConnectionError
    failed_lock(my_token, nil)
  end


  def steal_election!
    logger.warn "Stealing election"
    @resign_until = nil
    me = my_token
    server.set(key, me)
    got_lock(me)
    true
  rescue ZeevexCluster::Coordinator::ConnectionError
    false
  end

  protected

  def spin
    logger.debug "spin started"
    @state = :started
    run_hook :started
    run_hook :joined_cluster, cluster_name
    while @state == :started
      begin
        campaign
        if @state == :started
          begin
            sleep [@update_period - 1, 1].max
          rescue StopException
            logger.debug 'Stopping on stop exception'
          end
        end
      rescue ZeevexCluster::Coordinator::ConnectionError
        connection_error
      end
    end
  ensure
    @state = :stopped
    run_hook :left_cluster, cluster_name
    change_cluster_status :offline
    run_hook :stopped
  end

  def connection_error
    run_hook :connection_error
    change_cluster_status :offline
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

  def change_master_status(status, attrs = {})
    return if status == @master_status

    old_status, @master_status = @master_status, status
    run_hook :master_status_change, status, old_status, attrs
  end

  def change_cluster_status(status, attrs = {})
    return if status == @cluster_status

    old_status, @cluster_status = @cluster_status, status
    run_hook :cluster_status_change, status, old_status, attrs
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
      change_master_status :good
      @current_master  = token
    else
      change_my_status :master_elect
      change_master_status :waiting_for_inauguration
      run_hook :waiting_for_inauguration
      @current_master  = nil
    end
  end

  def failed_lock(me, winner)
    @locked_at       = nil

    if qualifies_for_master?(winner)
      @current_master = winner
      change_my_status :member
      change_master_status :good
    elsif ! token_invalid?(winner)
      @current_master = winner
      change_master_status :waiting_for_inauguration
    else
      @current_master = nil
      change_master_status :none
    end
    run_hook :election_lost, @current_master

    if @my_cluster_status == :master
      @my_master_token = nil
      change_my_status :lame_duck
      run_hook :lame_duck
    else
      change_my_status :member
    end
  end

  #
  # Must have held lock for INAUGURATION_UPDATE_DELAY update periods
  #
  def qualifies_for_master?(token)
    now = Time.now
    ! token_invalid?(token) and
        token[:timestamp] > (now - @stale_time) and
        token[:locked_at] <= (now - INAUGURATION_UPDATE_DELAY * @update_period)
  end

  def token_invalid?(token)
    now = Time.now
    !token || !token.is_a?(Hash) || !token[:timestamp] ||
        ! token[:locked_at] || ! token[:nodename] ||
        token[:timestamp] < (now - @stale_time)
  end

  def resigned?
    @resign_until && @resign_until > Time.now
  end

  def campaign
    me = my_token

    act_resigned = resigned?
    compete_for_token = !act_resigned

    hook = nil
    current = nil
    res = server.cas(key) do |val|
      current = val
      if is_me?(val) && !token_invalid?(val) && compete_for_token
        me
      elsif token_invalid?(val) && compete_for_token
        if is_me?(val)
          logger.info "My old token is invalid, refreshing: #{val.inspect}"
        else
          logger.info "CAS: master invalid, stealing: #{val.inspect}"
          # it's necessary to run this outside of the CAS block to be sure we won
          hook = :deposed_master
        end
        me
      else
        run_hook :suspect_master if @master_status != :none && master_suspect?(val)
        raise ZeevexCluster::Coordinator::DontChange
      end
    end

    # if we got a result, we must be online
    change_cluster_status :online

    if act_resigned
      run_hook :staying_resigned
      failed_lock(me, current)
      return
    else
      @resign_until = nil
    end

    if res
      run_hook hook if hook && res
      got_lock(me)
      return true
    elsif res == nil
      if server.add(key, me)
        logger.debug 'CAS: added frist post!'
        got_lock(me)
        return true
      end
    end

    if res
      got_lock(me)
      return true
    end

    # didn't get it
    failed_lock(me, current)
    false
  rescue ZeevexCluster::Coordinator::ConnectionError
    connection_error
    failed_lock(me, current)
    false
  end

  #
  # has the master gone without updating suspiciously long?
  #
  def master_suspect?(token)
    Time.now - token[:timestamp] > SUSPECT_MISSED_UPDATE_COUNT * @update_period
  end

  def reset_state_vars
    @resign_until = nil
    @my_master_token = nil
    @current_master = nil
    @state = :stopped
    @thread = nil
    @my_cluster_status = :nonmember
    @master_status = :none
    @cluster_status = :offline
  end
end
