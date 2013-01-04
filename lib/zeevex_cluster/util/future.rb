require 'observer'
require 'timeout'

class ZeevexCluster::Util::Future
  include Observable

  def initialize(computation = nil, &block)
    if computation && block
      raise ArgumentError, "must supply a callable OR a block or neither, but not both"
    end
    @computation = computation || block
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
  def _execute
    raise ArgumentError, "Cannot execute if callable not provided at initialization" unless @computation
    @executed = true
    @queue << @computation.call
  rescue Exception
    @exception = $!
    @queue    << $!
  ensure
    changed
    notify_observers
  end

  def execute
    @mutex.synchronize do
      _execute
    end
  end

  def call
    execute
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
      _execute
    end
  end

  def wait(timeout = nil)
    Timeout::timeout(timeout) do
      value
      true
    end
  rescue Timeout::Error
    false
  end
end
