module ZeevexCluster
  class Unclustered < Base
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
    ## We're unclustered, so we're always the master
    ##
    def master?
      true
    end

    ##
    ## Make this node the master, returning true if successful. No-op for now.
    ##
    def make_master!
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
      nodename
    end

  end
end
