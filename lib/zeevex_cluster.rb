module ZeevexCluster
  class ClusterException < StandardError; end
  class NotMaster < ClusterException; end
  class AlreadyMaster < ClusterException; end
  class ClusterPolicyViolation < ClusterException; end
  class ClusterActionFailed < ClusterException; end

  def self.logger
    @logger
  end

  def self.logger=(logger)
    @logger = ZeevexCluster::Synchronized(logger)
  end
end

require 'zeevex_cluster/synchronized'

require 'logger'
require 'zeevex_cluster/nil_logger'

ZeevexCluster.logger = ZeevexCluster::NilLogger.new

require 'zeevex_cluster/util'
require 'zeevex_cluster/base'
require 'zeevex_cluster/strategy'
require 'zeevex_cluster/coordinator'
require 'zeevex_cluster/election'
require 'zeevex_cluster/message'
