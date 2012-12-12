require 'zeevex_cluster/strategy/cas'

module ZeevexCluster
  class Memcached < Base

    def initialize(options = {})
      super
      raise ArgumentError, 'Must specify :cluster_name' unless options[:cluster_name]

      @strategy = ZeevexCluster::Strategy::Cas.new({:nodename => Socket.gethostname}.merge(options))

      after_initialize
    end

    def master?
      @strategy.am_i_master?
    end

    ##
    ## Make this node the master, returning true if successful. No-op for now.
    ##
    def make_master!
      #raise ClusterActionFailed, "Can not change master" unless master?
      #raise AlreadyMaster, "This node is already the master" if master?
      if @strategy.steal_election!
        true
      else
        false
      end
    end

    ##
    ## Resign from mastership; returns false if this is the only node.
    ##
    ## No-op for now.
    ##
    def resign!(delay = nil)
      @strategy.resign delay
      ## FIXME: is this a good idea?
      # @strategy.stop if @strategy.started? && delay == nil
    end

    def campaign!
      @strategy.start unless @strategy.started?
      # stop sitting out the election
      @strategy.resign 0
    end

    ##
    ## Return name of master node
    ##
    def master
      @strategy.master_node && @strategy.master_node[:nodename]
    end

    def join
      return if member?
      @member = true
      @strategy.start unless @strategy.started?
    end

    def leave
      return unless member?
      @member = false
      resign! if master?
      @strategy.stop if @strategy.started?
    end

    def member?
      @member
    end
  end
end
