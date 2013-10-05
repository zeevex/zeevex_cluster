require 'zeevex_cluster/strategy/base'
require 'socket'
require 'logger'

class ZeevexCluster::Strategy::Cas < ZeevexCluster::Strategy::Base

  attr_accessor :stale_time, :update_period, :server, :nodename, :cluster_name

  SUSPECT_MISSED_UPDATE_COUNT = 3
  INAUGURATION_UPDATE_DELAY   = 2

  def initialize(options = {})
    super
    @stale_time    = options.fetch(:stale_time, 40)
    @update_period = options.fetch(:update_period, 10)

    unless (@server = options[:coordinator])
      coordinator_type = options[:coordinator_type] || 'memcached'
      @server = ZeevexCluster::Coordinator.create(coordinator_type,
                                                  {:server     => options[:server],
                                                   :port       => options[:port],
                                                   :client     => options[:client],
                                                   :expiration => @stale_time * 4}.merge(options[:coordinator_options] || {}))
    end
    unless @server.is_a?(ZeevexCluster::Synchronized)
      @server = ZeevexCluster.Synchronized(@server)
    end
  end

  def do_i_hold_lock?
    @my_cluster_status == :master || @my_cluster_status == :master_elect
  end

  def master_node
    @current_master
  end

  def master_nodename
    @current_master && @current_master[:nodename]
  end

  class StopException < StandardError; end

  def start
    raise "Already started" if @thread || @state == :started
    @start_time = time_now
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
      @resign_until = time_now + (delay || [@update_period*6, @stale_time].min)
      current = nil
      server.cas(key) do |val|
        current = val
        if is_me?(val)
          my_token.merge(:timestamp => time_now - 2*@stale_time)
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

  def members
    stale_point = time_now - @stale_time
    list = server.get(key('members')) || make_member_list
    members = []
    list[:members].values.each do |v|
      members << v[:nodename] unless time_of(v[:timestamp]) < stale_point
    end
    members
  end

  def can_view?
    true
  end

  def observing?
    true
  end

  #
  # grab a snapshot of the cluster
  #
  def observe
    token = server.get(key)
    @current_master = qualifies_for_master?(token) ? token : nil
    {:master => @current_master, :members => members}
  end

  protected

  def spin
    logger.debug "spin started"
    @state = :started
    run_hook :started
    run_hook :joined_cluster, cluster_name
    while @state == :started
      begin
        register
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
    ignoring_connection_error { resign } if do_i_hold_lock?
    ignoring_connection_error { unregister }
    @state = :stopped
    run_hook :left_cluster, cluster_name
    change_cluster_status :offline
    run_hook :stopped
  end

  def ignoring_connection_error
    begin
      yield
    rescue ZeevexCluster::Coordinator::ConnectionError
      logger.debug 'got connection error in ignoring_connection_error'
      $!
    end
  end

  def connection_error
    run_hook :connection_error
    change_cluster_status :offline
  end
  
  def my_token
    now = time_now
    {:nodename    => nodename,
     :joined_at   => @start_time,
     :locked_at   => @locked_at || now,
     :timestamp   => now}
  end

  def key(subkey = 'throne')
    (@options[:cluster_key] || cluster_name) + ":" + subkey
  end

  def is_me?(token)
    token && token.is_a?(Hash) && token[:nodename] == nodename
  end


  def got_lock(token)
    unless @locked_at
      @locked_at     = time_of(token[:timestamp])
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
    now = time_now()
    ! token_invalid?(token) and
        time_of(token[:timestamp]) > (now - @stale_time) and
        time_of(token[:locked_at]) <= (now - INAUGURATION_UPDATE_DELAY * @update_period)
  end

  def time_now
    Time.now.utc
  end

  def token_invalid?(token)
    now = time_now
    !token || !token.is_a?(Hash) || !token[:timestamp] ||
        ! token[:locked_at] || ! token[:nodename] ||
        time_of(token[:timestamp]) < (now - @stale_time)
  end

  def resigned?
    @resign_until && @resign_until > time_now
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
    elsif res.nil?
      failed_lock(me, nil)
      if server.add(key, me)
        logger.debug 'CAS: added frist post!'
        got_lock(me)
        return true
      end
    end

    # CAS succeeded so we're the boss
    if res
      got_lock(me)
      true

    # didn't get it, somebody else must be boss
    else
      failed_lock(me, current)
      false
    end
  rescue ZeevexCluster::Coordinator::ConnectionError
    connection_error
    failed_lock(me, current)
    false
  end

  def make_member_list
    {:members => {@nodename => my_token}}
  end

  def register
    me = my_token

    self_key = self.key('member:' +  @nodename)
    memberlist_key = self.key('members')
    server.set(self_key, me) or raise "failed to set #{self_key}"

    res = false
    retries = 5

    while retries > 0 && res == false
      stale_point = time_now - @stale_time
      res = server.cas(memberlist_key) do |hash|
        hash[:members] ||= {}
        hash[:members].keys.each do |key|
          hash[:members].delete(key) if time_of(hash[:members][key][:timestamp]) < stale_point
        end
        hash[:members][@nodename] = me
        hash
      end
      retries -= 1
    end

    if res.nil?
      server.add(memberlist_key, {:members => {@nodename => me}})
    end

    true
  rescue ZeevexCluster::Coordinator::ConnectionError
    connection_error
    false
  end

  def unregister
    me = my_token

    self_key = self.key('member:' +  @nodename)
    memberlist_key = self.key('members')
    server.delete(self_key)

    res = false
    retries = 5

    while retries > 0 && res == false
      res = server.cas(memberlist_key) do |hash|
        hash[:members] ||= {}
        hash[:members].delete @nodename
        hash
      end
      retries -= 1
    end

    true
  rescue ZeevexCluster::Coordinator::ConnectionError
    connection_error
    false
  end

  #
  # has the master gone without updating suspiciously long?
  #
  def master_suspect?(token)
    time_now - time_of(token[:timestamp]) > SUSPECT_MISSED_UPDATE_COUNT * @update_period
  end

  def reset_state_vars
    super

    @resign_until = nil
    @my_master_token = nil
    @current_master = nil
    @thread = nil
  end

  def time_of(timelike)
    res = case timelike
            when DateTime then timelike.to_time
            when Time     then timelike
            when String   then time_of(DateTime.parse(timelike))
            when Integer  then Time.at(timelike)
            when nil      then nil
            else
              raise ArgumentError, "Cannot parse #{timelike.inspect} of class #{timelike.class} to a time"
          end
    res.respond_to?(:utc) ? res.utc : res
  end

end
