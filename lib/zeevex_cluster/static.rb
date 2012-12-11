module ZeevexCluster
  class Static < Base
    def initialize(options = {})
      super
      raise ArgumentError, "Must supply :master_nodename" unless @options[:master_nodename]
      if @options[:master_nodename] == :self
        @options[:master_nodename] = nodename
      end
    end

    ##
    ## joining is a no-op for ol' singleton here
    ##
    def join
      true
    end

    ##
    ## leaving, too
    ##
    def leave
      true
    end

    ##
    ## Are we the chosen one?
    ##
    def master?
      nodename == options[:master_nodename]
    end

    ##
    ## Nobody can change the master
    ##
    def make_master!
      raise ClusterActionFailed, "Can not change master" unless master?
      true
    end

    ##
    ## Resign from mastership; returns false if this is the only node.
    ##
    ## No-op for now.
    ##
    def resign!
      raise NotMaster unless master?

      # master is currently fixed, so we can't resign
      raise ClusterPolicyViolation, "Current master cannot resign in this implementation."
    end

    ##
    ## Return name of master node
    ##
    def master
      options[:master_nodename]
    end

  end
end
