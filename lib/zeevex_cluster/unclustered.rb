require 'zeevex_cluster/static'

module ZeevexCluster
  class Unclustered < Static
    def initialize(options = {})
      raise ArgumentError, "Cannot specify master nodename" if options.include?(:master_nodename)
      options[:master_nodename] = :self
      super
    end
  end
end
