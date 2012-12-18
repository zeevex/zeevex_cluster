module ZeevexCluster::Strategy
  class Unclustered < Static
    def initialize(options)
      options[:master_nodename] = options[:nodename]
      super
      @members = [@nodename]
    end
  end
end
