require 'observer'
require 'timeout'
require 'zeevex_cluster/util/delayed'

class ZeevexCluster::Util::Promise < ZeevexCluster::Util::Delayed
  include Observable
  include ZeevexCluster::Util::Delayed::Bindable
  include ZeevexCluster::Util::Delayed::QueueBased

  def initialize(computation = nil, options = {}, &block)
    @mutex       = Mutex.new
    @exec_mutex  = Mutex.new
    @exception   = nil
    @done        = false
    @result      = false
    @executed    = false

    _initialize_queue

    # has to happen after exec_mutex initialized
    bind(computation, &block) if (computation || block)

    Array(options.delete(:observer) || options.delete(:observers)).each do |observer|
      self.add_observer observer
    end
  end

  def self.create(callable = nil, options = {}, &block)
    return callable if callable && callable.is_a?(ZeevexCluster::Util::Delayed)
    new(callable, options, &block)
  end
end
