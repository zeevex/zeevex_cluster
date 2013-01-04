require 'thread'

#
# base class for Promise, Future, etc.
#
class ZeevexCluster::Util::Delayed

  def exception
    @mutex.synchronize do
      @exception
    end
  end

  def exception?
    !! @exception
  end

  def ready?
    @mutex.synchronize do
      @executed || @done
    end
  end

  def value(reraise = true)
    @mutex.synchronize do
      unless @done
        @result = _wait_for_value
        @done   = true
      end
      if @exception && reraise
        raise @exception
      else
        @result
      end
    end
  end

  def wait(timeout = nil)
    Timeout::timeout(timeout) do
      value(false)
      true
    end
  rescue Timeout::Error
    false
  end

  def set_result(&block)
    @exec_mutex.synchronize do
      raise ArgumentError, "Must supply block" unless block_given?
      raise ArgumentError, "Already supplied block" if bound?
      raise ArgumentError, "Promise already executed" if @executed || @done

      _execute(block)
    end
  end

  protected

  #
  # not MT-safe; only to be called from executor thread
  #
  def _execute(computation)
    raise ArgumentError, "Cannot execute without computation" unless computation
    res = nil
    _fulfill(res = computation.call)
  rescue Exception
    _smash($!)
  ensure
    @executed = true
  end


  def _smash(ex)
    @exception = ex
    _fulfill ex, false
  end

  ###

  module QueueBased
    protected

    def _initialize_queue
      @queue = Queue.new
    end

    def _fulfill(value, success = true)
      @queue << value
      if respond_to?(:notify_observers)
        changed
        notify_observers(self, value, success)
      end
    end

    def _wait_for_value
      @queue.pop
    end
  end

  module Bindable
    def bound?
      !! @binding
    end

    def binding
      @binding
    end

    def bind(proccy = nil, &block)
      @exec_mutex.synchronize do
        raise "Already bound" if bound?
        if proccy && block
          raise ArgumentError, "must supply a callable OR a block or neither, but not both"
        end
        raise ArgumentError, "Must provide computation as proc or block" unless (proccy || block)
        @binding = proccy || block
      end
    end

    def execute
      @exec_mutex.synchronize do
        _execute(binding)
      end
    end

    def call
      execute
    end

  end
end
