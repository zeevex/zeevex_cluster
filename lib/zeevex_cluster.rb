module ZeevexCluster
  class ClusterException < StandardError; end
  class NotMaster < ClusterException; end
  class AlreadyMaster < ClusterException; end
  class ClusterPolicyViolation < ClusterException; end
  class ClusterActionFailed < ClusterException; end
end

require 'zeevex_cluster/base'
require 'zeevex_cluster/static'
require 'zeevex_cluster/unclustered'
require 'zeevex_cluster/strategy'
require 'zeevex_cluster/coordinator'
