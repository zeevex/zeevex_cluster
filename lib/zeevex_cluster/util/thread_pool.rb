require 'zeevex_cluster/util'
require 'zeevex_cluster/util/event_loop'
require 'thread'

module ZeevexCluster::Util::ThreadPool
  module Stubs
    def busy?
      free_count == 0
    end

    def worker_count
      -1
    end

    def busy_count
      -1
    end

    def free_count
      (worker_count - busy_count)
    end

    #
    # how many tasks are waiting
    #
    def backlog
      0
    end
  end
  #
  # Use a single-threaded event loop to process jobs
  #
  class EventLoopAdapter
    include Stubs

    def initialize(loop = nil)
      @loop ||= ZeevexUtil::Util.EventLoop.new
      start
    end

    def start
      @loop.start
    end

    def stop
      @loop.stop
    end

    def join
      stop
    end

    def enqueue(callable = nil, &block)
      @loop.enqueue callable, &block
    end
  end

  #
  # Run job semi-synchronously (on a separate thread, but block on it)
  # We use a separate thread
  #
  class InlineThreadPool
    include Stubs

    def initialize(loop = nil)
      start
    end

    def start
      @started = true
    end

    def stop
      @started = false
    end

    def join
      stop
    end

    def enqueue(callable = nil, &block)
      raise "Must be started" unless @started
      thr = Thread.new do
        (callable || block).call
      end
      thr.join
    end
  end

  #
  # Launch a concurrent thread for every new task enqueued
  #
  class ThreadPerJobPool
    include Stubs

    def initialize
      @mutex = Mutex.new
      @group = ThreadGroup.new

      start
    end

    def enqueue(runnable = nil, &block)
      thr = Thread.new do
        (runnable || block).call
      end
      @group.add(thr)
    end

    def start
      @started = true
    end

    def join
      @group.list.each do |thr|
        thr.join
      end
    end

    def stop
      @mutex.synchronize do
        return unless @started

        @group.list.each do |thr|
          thr.kill
        end

        @started = false
      end
    end
  end

  #
  # Use a fixed pool of N threads to process jobs
  #
  class FixedPool
    def initialize(count = -1)
      if count == -1
        count = ZeevexCluster::Util::ThreadPool.cpu_count * 2
      end
      @count = count
      @queue = Queue.new
      @mutex = Mutex.new
      @group = ThreadGroup.new
      @busy_count = 0

      start
    end

    def enqueue(runnable = nil, &block)
      @queue << (runnable || block)
    end

    def start
      @mutex.synchronize do
        return if @started

        @stop_requested = false

        @count.times do
          thr = Thread.new(@queue) do
            while !@stop_requested
              begin
                work = @queue.pop
                @mutex.synchronize { @busy_count += 1 }
                work.call
                @mutex.synchronize { @busy_count -= 1 }
              rescue Exception
                ZeevexCluster.logger.error %{Exception caught in thread pool: #{$!.inspect}: #{$!.backtrace.join("\n")}}
              end
            end
          end
          @group.add(thr)
        end

        @started = true
      end
    end

    def join
      @mutex.synchronize do
        raise "Joining will fail unless pool has been asked to stop" if @started
        @group.each do |thr|
          thr.join
        end
      end
    end

    def stop
      @mutex.synchronize do
        return unless @started

        @stop_requested = true

        @group.list.each do |thr|
          thr.kill
        end

        @busy_count = 0
        @started = false
      end
    end

    def busy?
      free_count == 0
    end

    def worker_count
      @count
    end

    def busy_count
      @busy_count
    end

    def free_count
      (worker_count - busy_count)
    end

    #
    # how many tasks are waiting
    #
    def backlog
      @queue.size
    end
  end

  #
  # Return the number of CPUs reported by the system
  #
  def self.cpu_count
    return Java::Java.lang.Runtime.getRuntime.availableProcessors if defined? Java::Java
    return File.read('/proc/cpuinfo').scan(/^processor\s*:/).size if File.exist? '/proc/cpuinfo'
    require 'win32ole'
    WIN32OLE.connect("winmgmts://").ExecQuery("select * from Win32_ComputerSystem").NumberOfProcessors
  rescue LoadError
    Integer `sysctl -n hw.ncpu 2>/dev/null` rescue 1
  end
end
