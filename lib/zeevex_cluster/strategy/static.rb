require 'zeevex_cluster/strategy/base'

module ZeevexCluster::Strategy
  class Static < Base
    def initialize(options = {})
      super
      @master_nodename = options[:master_nodename] || raise(ArgumentError, 'Must specify :master_nodename')
      @members = options[:members]
    end

    def start
      @state  = :started
      change_cluster_status :online
      if @nodename == @master_nodename
        change_my_status :master
        change_master_status :good
      else
        change_my_status :member
        change_master_status :unknown
      end
    end

    def stop
      @state = :stopped
      change_my_status :nonmember
      change_master_status :unknown
      change_cluster_status :offline
    end

    def am_i_master?
      @state == :started && @my_cluster_status == :master
    end

    # FIXME: this is CAS-specific
    def master_node
      {:nodename => @master_nodename}
    end

    def members
      @members || [@master_nodename, @nodename].select {|x| x != "none" }.uniq
    end

    def resign(delay = nil)
      # master is currently fixed, so we can't resign
      logger.warn 'Current master cannot resign in this implementation.'
      false
    end

    def steal_election!
      raise ClusterActionFailed, 'Can not change master' unless am_i_master?
      true
    end

  end
end
