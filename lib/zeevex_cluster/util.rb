module ZeevexCluster
  module Util
    module All
      def self.included(base)
        base.class_eval do
          include Hookem
          include ZeevexCluster::Util::Logging
        end
      end
    end
  end
end

require 'zeevex_cluster/util/logging'
require 'hookem'
