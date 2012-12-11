module ZeevexCluster
  class ClusterException < StandardError; end
  class NotMaster < ClusterException; end
  class AlreadyMaster < ClusterException; end
  class ClusterPolicyViolation < ClusterException; end
  class ClusterActionFailed < ClusterException; end

  # Your code goes here...
  class << self
    ##
    ## XXX: obviously this is just a stub
    ##
    def master?
      true
    end

    ##
    ## Make this node the master, returning true if successful. No-op for now.
    ##
    def make_master!
      raise ClusterActionFailed, "Can not change master" unless master?
      raise AlreadyMaster, "This node is already the master" if master?
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
      case Rails.env.to_sym
      when :production then "prod1.eng.zeevex.com"
      else nodename
      end
    end

    ##
    ## Return this node's name
    ##
    def nodename
      Socket.gethostname
    end
    
  end

end
