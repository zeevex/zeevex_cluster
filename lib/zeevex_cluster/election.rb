require 'zeevex_cluster/strategy'
require 'zeevex_cluster/strategy/cas'

module ZeevexCluster
  class Election < Base

    def initialize(options = {})
      super
      raise ArgumentError, 'Must specify :cluster_name' unless options[:cluster_name]

      if options[:hooks]
        add_hooks(options[:hooks])
      end

      unless (@strategy = options[:strategy])
        stype = options[:strategy_type] || 'cas'
        @strategy = ZeevexCluster::Strategy.create(stype,
                                                   {:nodename         => options.fetch(:nodename, Socket.gethostname),
                                                    :cluster_name     => options[:cluster_name],
                                                    :logger           => options[:logger]}.
                                                       merge(options[:backend_options]))
      end
      @strategy.add_hook_observer Proc.new { |*args| hook_observer(*args) }

      after_initialize
    end

    def master?
      @strategy.am_i_master?
    end

    ##
    ## Make this node the master, returning true if successful. No-op for now.
    ##
    def make_master!
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
      resign! if master?
      @strategy.stop if @strategy.started?
    ensure
      @member = false
    end

    def member?
      @member
    end

    def members
      @strategy.respond_to?(:members) ? @strategy.members : [@nodename]
    end

    protected

    def hook_observer(hook_name, source, *args)
      logger.debug "#{self.class} observed hook: #{hook_name} #{args.inspect}"
      case hook_name
        when :status_change
          run_hook :status_change, args[0], args[1]
        when :cluster_status_change
          run_hook :cluster_status_change, args[0], args[1]
        else
          run_hook "strategy_#{hook_name}".to_sym, *args
      end
    end
  end
end
