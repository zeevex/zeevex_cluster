require 'observer'
require 'timeout'
require 'zeevex_cluster/util/delayed'

class ZeevexCluster::Util::Promise < ZeevexCluster::Util::Delayed
  include Observable
  include ZeevexCluster::Util::Delayed::Bindable
  include ZeevexCluster::Util::Delayed::QueueBased

  def initialize(computation = nil, &block)
    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @done        = false
    @result      = false
    @executed    = false

    _initialize_queue

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)
  end

  def self.create(callable = nil, &block)
    return callable if callable && callable.is_a?(ZeevexCluster::Util::Delayed)
    new(callable, &block)
  end
end
