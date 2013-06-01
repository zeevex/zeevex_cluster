module ZeevexCluster::Util
  module Logging
    def logger
      @logger || ZeevexCluster.logger
    end
  end
end
