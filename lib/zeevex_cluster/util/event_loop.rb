require 'thread'
require 'zeevex_cluster/util/promise'

module ZeevexCluster::Util
  class EventLoop
    def initialize(options = {})
      @options = options
      @mutex   = options.delete(:mutex) || Mutex.new
      @queue   = options.delete(:queue) || Queue.new
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
      unless @thread.join(1)
        @thread.kill
        @thread.join(0)
      end

      @thread = nil
      @state = :stopped
    end

    #
    # Enqueue any callable object (including a Promise or Future or other Delayed class) to the event loop
    # and return a Delayed object which can be used to fetch the return value.
    #
    # Strictly obeys ordering.
    #
    def enqueue(callable = nil, &block)
      to_run = callable || block
      raise ArgumentError, "Must provide proc or block arg" unless to_run

      to_run = ZeevexCluster::Util::Promise.new(to_run) unless to_run.is_a?(ZeevexCluster::Util::Delayed)
      @queue << to_run
      to_run
    end

    def <<(callable)
      enqueue(callable)
    end

    def flush
      @queue.clear
    end

    def reset
      stop
      flush
      start
    end

    #
    # Returns true if the method was called from code executing on the event loop's thread
    #
    def in_event_loop?
      Thread.current.object_id == @thread.object_id
    end

    #
    # Runs a computation on the event loop. Does not deadlock if currently on the event loop, but
    # will not preserve ordering either - it runs the computation immediately despite other events
    # in the queue
    #
    def on_event_loop(runnable = nil, &block)
      return unless runnable || block_given?
      promise = (runnable && runnable.is_a?(ZeevexCluster::Util::Delayed)) ?
                 runnable :
                 ZeevexCluster::Util::Promise.create(runnable, &block)
      if in_event_loop?
        promise.call
        promise
      else
        enqueue promise, &block
      end
    end

    #
    # Returns the value from the computation rather than a Promise.  Has similar semantics to
    # `on_event_loop` - if this is called from the event loop, it just executes the
    # computation synchronously ahead of any other queued computations
    #
    def run_and_wait(runnable = nil, &block)
      promise = on_event_loop(runnable, &block)
      promise.value
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

    public

    # event loop which throws away all events without running, returning nil from all promises
    class Null
      def initialize(options = {}); end
      def start; end
      def stop; end
      def enqueue(callable = nil, &block)
        to_run = ZeevexCluster::Util::Promise.new unless to_run.is_a?(ZeevexCluster::Util::Delayed)
        to_run.set_result { nil }
        to_run
      end
      def in_event_loop?; false; end
      def on_event_loop(runnable = nil, &block)
        enqueue(runnable, &block)
      end
    end

    # event loop which runs all events synchronously when enqueued
    class Inline < ZeevexCluster::Util::EventLoop
      def start; end
      def stop; end
      def enqueue(callable = nil, &block)
        res = super
        @queue.pop.call
        res
      end
      def in_event_loop?; true; end
    end

  end
end
