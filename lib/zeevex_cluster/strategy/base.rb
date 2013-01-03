require 'zeevex_cluster/strategy'
# require 'zeevex_threadsafe/thread_safer'

module ZeevexCluster::Strategy
  class Base
    include ZeevexCluster::Util::Logging
    include ZeevexCluster::Util::Hooks
    # include ZeevexThreadsafe::ThreadSafer

    def initialize(options = {})
      @options       = options
      @namespace     = options[:namespace]
      @cluster_name  = options[:cluster_name]
      @nodename      = options[:nodename] || Socket.gethostname
      @hooks         = {}
      @logger        = options[:logger]

      @state         = :stopped

      reset_state_vars

      if options[:hooks]
        add_hooks options[:hooks]
      end
    end

    def has_master?
      !! @current_master
    end

    def am_i_master?
      @my_cluster_status == :master
    end

    def state
      @state
    end

    def online?
      @cluster_status == :online
    end

    def member?
      online?
    end

    def started?
      @state == :started
    end

    def stopped?
      @state == :stopped
    end

    protected

    def change_my_status(status, attrs = {})
      return if status == @my_cluster_status

      old_status = @my_cluster_status
      @my_cluster_status = status
      run_hook :status_change, status, old_status, attrs
    end

    def change_master_status(status, attrs = {})
      return if status == @master_status

      old_status, @master_status = @master_status, status
      run_hook :master_status_change, status, old_status, attrs
    end

    def change_cluster_status(status, attrs = {})
      return if status == @cluster_status

      old_status, @cluster_status = @cluster_status, status
      run_hook :cluster_status_change, status, old_status, attrs
    end

    def reset_state_vars
      @state = :stopped
      @my_cluster_status = :nonmember
      @master_status = :none
      @cluster_status = :offline
    end

    # make_thread_safe :change_my_status, :change_master_status, :change_cluster_status
  end
end
