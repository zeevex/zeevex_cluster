require 'thread'

#
# base class for Promise, Future, etc.
#
class ZeevexCluster::Util::Delayed

  module ConvenienceMethods
    def future(*args, &block)
      ZeevexCluster::Util::Future.__send__(:create, *args, &block)
    end

    def promise(*args, &block)
      ZeevexCluster::Util::Promise.__send__(:create, *args, &block)
    end

    def delay(*args, &block)
      ZeevexCluster::Util::Delay.__send__(:create, *args, &block)
    end

    def delayed?(obj)
      obj.is_a?(ZeevexCluster::Util::Delayed)
    end

    def delay?(obj)
      obj.is_a?(ZeevexCluster::Util::Delay)
    end

    def promise?(obj)
      obj.is_a?(ZeevexCluster::Util::Promise)
    end

    def future?(obj)
      obj.is_a?(ZeevexCluster::Util::Future)
    end
  end

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
      executed?
    end
  end

  def executed?
    @executed
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
      raise ArgumentError, "Promise already executed" if executed?

      _execute(block)
    end
  end

  def executed?
    @executed
  end

  protected

  #
  # not MT-safe; only to be called from executor thread
  #
  def _execute(computation)
    raise "Already executed" if executed?
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
        return if executed?
        return if respond_to?(:cancelled?) && cancelled?
        _execute(binding)
      end
    end

    def call
      execute
    end
  end

  module Cancellable
    def cancelled?
      @canceled
    end

    def cancel
      @exec_mutex.synchronize do
        return false if executed?
        return true if cancelled?
        @canceled = true
        _smash CancelledException.new
      end
    end

    def ready?
      cancelled? || super
    end
  end

  class CancelledException < StandardError; end
end

module ZeevexCluster::Util
  extend(ZeevexCluster::Util::Delayed::ConvenienceMethods)
end
