require 'thread'

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

    def enqueue(runnable = nil, &block)
      if runnable
        @queue << runnable
      elsif block
        @queue << block
      else
        raise ArgumentError, "Must provide proc or block arg"
      end
    end

    def in_event_loop?
      Thread.current == @thread
    end

    def on_event_loop(runnable = nil, &block)
      return unless runnable || block_given?
      if in_event_loop?
        (runnable || block).call
      else
        enqueue runnable, &block
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

    public

    class Future
      def initialize(computation)
        @computation = computation
        @mutex       = Mutex.new
        @queue       = Queue.new
        @exception   = nil
        @done        = false
        @result      = false
        @executed    = false
      end

      #
      # not MT-safe; only to be called from executor thread
      #
      def execute
        @executed = true
        @queue << @computation.call
      rescue Exception
        @exception = $!
        @queue    << $!
      end

      def exception
        @mutex.synchronize do
          @exception
        end
      end

      def exception?
        !! @exception
      end

      def value(reraise = true)
        @mutex.synchronize do
          unless @done
            @done   = true
            @result = @queue.pop
          end
          if @exception && reraise
            raise @exception
          else
            @result
          end
        end
      end

      def ready?
        @mutex.synchronize do
          ! @done && ! @queue.empty?
        end
      end

      def set_result(&block)
        @mutex.synchronize do
          raise ArgumentError, "Must supply block" unless block_given?
          raise ArgumentError, "Already supplied block" if @computation
          raise ArgumentError, "Future already executed" if @done

          @computation = block
          execute
        end
      end

      #def wait(timeout = nil)
      #  @queue.wait timeout
      #end
    end
  end
end
