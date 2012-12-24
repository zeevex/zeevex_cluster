require 'zeevex_cluster/strategy/base'
require 'zk'
require 'zk/election'

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
      @zk.close
      @state = :stopped
      true
    end

    def am_i_master?
      @elector.leader?
    end

    def master_node
      {:nodename => @elector.leader_data}
    end

    def members
      root = @elector.root_vote_path
      @zk.children(root).select {|f| f.start_with? "ballot" }.map do |name|
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

    protected

    def setup
      logger.debug "ZK: setting up"

      @zk = ZK.new(@options[:host] || 'localhost:2181')
      @elector = ZK::Election::Candidate.new @zk, @cluster_name, :data => @nodename

      @zk.wait_until_connected

      change_cluster_status :online

      setup_winning_callback
      setup_losing_callback
      setup_leader_ack_callback

      # this thread will run until we win, in which case
      # the thread will exit and we'll be master.
      thr = Thread.new do
        @elector.vote!
      end
      thr.join
      logger.debug "ZK vote thread exited"
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
