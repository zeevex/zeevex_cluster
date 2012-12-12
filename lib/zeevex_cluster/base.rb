require 'socket'

module ZeevexCluster
  class Base
    attr_accessor :nodename, :options

    def initialize(options = {})
      @options = {:nodename => Socket.gethostname,
                  :autojoin => true}.merge(options)
    end

    def join
      raise NotImplementedError
    end

    def leave
      raise NotImplementedError
    end

    def master?
      raise NotImplementedError
    end

    def member?
      raise NotImplementedError
    end

    ##
    ## Make this node the master, returning true if successful.
    ##
    def make_master!
      raise NotImplementedError
    end

    ##
    ## Make this node the master if not already the master
    ## if provided a block, run that IFF we are the master
    ##
    def ensure_master(&block)
      make_master! unless master?
      if block
        run_if_master &block
      end
    end

    ##
    ## Run the code block only if this node is the master
    ##
    def run_if_master(&block)
      if master?
        block.call
      else
        false
      end
    end

    ##
    ## Resign from mastership; returns false if this is the only node.
    ##
    def resign!
      raise NotImplementedError
    end

    ##
    ## Return name of master node
    ##
    def master
      raise NotImplementedError
    end

    ##
    ## Return this node's name
    ##
    def nodename
      options[:nodename]
    end

    protected

    def after_initialize
      join if options.fetch(:autojoin, true)
    end
  end
end
