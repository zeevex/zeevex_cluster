require 'thread'
require 'zeevex_cluster/util/future'

module ZeevexCluster::Util
  class EventLoop
    def initialize(options = {})
      @options = options
      @mutex   = Mutex.new
      @queue   = Queue.new
      @state   = :stopped
    end

    def running?
      @state == :started
    end

    def start
      return unless @state == :stopped
      @stop_requested = false
      @thread = Thread.new do
        process
      end

      @state = :started
    end

    def stop
      return unless @state == :started
      enqueue { @stop_requested = true }
      @thread.join
      @thread = nil
      @state = :stopped
    end

    #
    # Enqueue a callable object (including a Future) and return
    # a Future object which can be used to fetch the return value
    #
    def enqueue(callable = nil, &block)
      to_run = callable || block
      raise ArgumentError, "Must provide proc or block arg" unless to_run

      to_run = ZeevexCluster::Util::Future.new(to_run) unless to_run.is_a?(ZeevexCluster::Util::Future)
      @queue << to_run
      to_run
    end

    def in_event_loop?
      Thread.current.object_id == @thread.object_id
    end

    def on_event_loop(runnable = nil, &block)
      return unless runnable || block_given?
      future = ZeevexCluster::Util::Future.new(runnable || block)
      if in_event_loop?
        future.execute
      else
        enqueue future, &block
      end
    end

    protected

    def process
      while !@stop_requested
        begin
          @queue.pop.call
        rescue
          ZeevexCluster.logger.error %{Exception caught in event loop: #{$!.inspect}: #{$!.backtrace.join("\n")}}
        end
      end
    end

  end
end
