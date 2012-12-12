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
    @logger = logger
  end
end

require 'logger'
require 'zeevex_cluster/nil_logger'

ZeevexCluster.logger = ZeevexCluster::NilLogger.new

require 'zeevex_cluster/util'
require 'zeevex_cluster/base'
require 'zeevex_cluster/static'
require 'zeevex_cluster/unclustered'
require 'zeevex_cluster/strategy'
require 'zeevex_cluster/coordinator'

