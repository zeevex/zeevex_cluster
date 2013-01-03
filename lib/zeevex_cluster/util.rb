module ZeevexCluster
  module Util
    module All
      def self.included(base)
        base.class_eval do
          include ZeevexCluster::Util::Hooks
          include ZeevexCluster::Util::Logging
          include ZeevexCluster::Util::EventLoop
        end
      end
    end
  end
end

require 'zeevex_cluster/util/logging'
require 'zeevex_cluster/util/event_loop'
require 'zeevex_cluster/util/hooks'
