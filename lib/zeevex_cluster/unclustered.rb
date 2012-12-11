require 'zeevex_cluster/static'

module ZeevexCluster
  class Unclustered < Static
    def initialize(options = {})
      options[:master_nodename] = :self
      super
    end
  end
end
