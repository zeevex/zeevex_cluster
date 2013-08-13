require 'edn'
require 'date'

require 'zeevex_cluster/serializer'

class ZeevexCluster::Serializer::EDN
  def new(options = {})
    @options = options
  end

  def deserialize(str)
    parsed = ::EDN.read(str)
  end

  def serialize(obj)
    obj.to_edn
  end
end
