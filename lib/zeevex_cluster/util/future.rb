require 'observer'
require 'timeout'
require 'zeevex_cluster/util/delayed'

class ZeevexCluster::Util::Future < ZeevexCluster::Util::Promise
  include Observable

  def initialize(computation = nil, &block)
    super
  end

end
