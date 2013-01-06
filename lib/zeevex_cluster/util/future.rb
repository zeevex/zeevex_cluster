require 'observer'
require 'timeout'
require 'zeevex_cluster/util/delayed'
require 'zeevex_cluster/util/event_loop'
require 'zeevex_cluster/util/thread_pool'

class ZeevexCluster::Util::Future < ZeevexCluster::Util::Delayed
  include Observable
  include ZeevexCluster::Util::Delayed::Bindable
  include ZeevexCluster::Util::Delayed::LatchBased
  include ZeevexCluster::Util::Delayed::Cancellable

  # @@worker_pool = ZeevexCluster::Util::EventLoop.new
  @@worker_pool = ZeevexCluster::Util::ThreadPool::FixedPool.new
  @@worker_pool.start

  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)

    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @done        = false
    @result      = false
    @executed    = false

    _initialize_latch

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      add_observer observer
    end
  end

  def self.shutdown
    self.worker_pool.stop
  end

  def self.create(callable=nil, options = {}, &block)
    nfuture = ZeevexCluster::Util::Future.new(callable, options, &block)
    (options.delete(:event_loop) || worker_pool).enqueue nfuture

    nfuture
  end

  def self.worker_pool
    @@worker_pool
  end

  def self.worker_pool=(pool)
    @@worker_pool = pool
  end

  class << self
    alias_method :future, :create
  end
end

