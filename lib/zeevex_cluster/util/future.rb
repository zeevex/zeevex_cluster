require 'observer'
require 'timeout'
require 'zeevex_cluster/util/delayed'
require 'zeevex_cluster/util/event_loop'

class ZeevexCluster::Util::Future < ZeevexCluster::Util::Promise
  include Observable

  @@worker_pool = ZeevexCluster::Util::EventLoop.new
  @@worker_pool.start

  def initialize(computation = nil, options = {}, &block)
    raise ArgumentError, "Must provide computation or block for a future" unless (computation || block)
    super(computation, &block)
    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      self.add_observer observer
    end
  end

  def self.shutdown
    self.worker_pool.stop
  end

  def self.create(callable=nil, options = {}, &block)
    future = new(callable, options, &block)

    (options.delete(:event_loop) || worker_pool).enqueue future

    future
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
