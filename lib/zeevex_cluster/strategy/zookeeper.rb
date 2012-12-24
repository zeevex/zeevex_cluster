require 'zeevex_cluster/strategy/base'
require 'zk'
require 'zk/election'
require 'zk-group'

module ZeevexCluster::Strategy
  class Zookeeper < Base
    def initialize(options = {})
      super
      ZK.logger = logger
    end

    def start
      return true if @state == :started
      setup
      @state = :started
    end

    def stop
      return true unless @state == :started
      @elector.close
      @grouper.close
      @zk.close
      @state = :stopped
      true
    end

    def am_i_master?
      @state == :started && @elector.leader?
    end

    def master_node
      @state == :started && {:nodename => @elector.leader_data}
    end

    def members_via_election
      return unless @state == :started

      root = @elector.root_vote_path
      @zk.children(root).select {|f| f.start_with? "ballot" }.map do |name|
        @zk.get(root + '/' + name)[0]
      end
    end

    def members
      @state == :started && @members
    end

    def data_for_grouper_members(*members)
      root = @grouper.path
      Array(members).flatten.map do |name|
        @zk.get(root + '/' + name)[0]
      end
    end

    def resign(delay = nil)
      return false
    end

    def steal_election!
      raise ClusterActionFailed, 'Can not change master' unless am_i_master?
      true
    end

    def cluster_key
      [@namespace, @cluster_name].reject {|x| x.nil? || x.empty? }.join(':')
    end

    protected

    def setup
      logger.debug "ZK: setting up"

      @zk = ZK.new(@options[:host] || 'localhost:2181')
      @zk.wait_until_connected

      @elector = ZK::Election::Candidate.new @zk, cluster_key, :data => @nodename
      @grouper = ZK::Group.new @zk, cluster_key

      change_cluster_status :online

      @members = []

      setup_winning_callback
      setup_losing_callback
      setup_leader_ack_callback

      @grouper.create
      @grouper.join @nodename

      @grouper.on_membership_change do |last_members, current_members|
        update_membership(last_members, current_members)

      end

      # this thread will run until we win, in which case
      # the thread will exit and we'll be master.
      thr = Thread.new do
        @elector.vote!
      end
      thr.join
      logger.debug "ZK vote thread exited"
    end

    def update_membership(last_members, current_members)
      old_membership = @members
      @members = data_for_grouper_members(current_members).freeze
      logger.debug "ZK: membership change from ZK::Group: from #{old_membership.inspect} to #{@members.inspect}"
      run_hook :membership_change, old_membership, @members
    end

    def setup_winning_callback
      @elector.on_winning_election do
        logger.debug "ZK: winning election!"
        change_my_status :master
        change_master_status :good
      end
    end

    def setup_losing_callback
      @elector.on_losing_election do
        logger.debug "ZK: losing election!"
        change_my_status :member
      end
    end

    def setup_leader_ack_callback
      @elector.on_leader_ack do
        logger.debug "ZK: leader ack!"
        change_master_status :good
      end
    end
  end
end
