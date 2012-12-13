require 'zeevex_cluster/strategy/cas'
require 'zeevex_cluster/coordinator/redis'
require 'zeevex_cluster/memcached'

module ZeevexCluster
  class Redis < Memcached

    def initialize(options = {})
      options[:backend_options] ||= {}
      options[:backend_options][:coordinator] =
          ZeevexCluster::Coordinator::Redis.new options[:backend_options].merge({:expiration => options.fetch(:expiration, 60)})

      super(options)
    end

  end
end
