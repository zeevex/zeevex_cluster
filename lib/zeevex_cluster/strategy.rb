module ZeevexCluster
  module Strategy
    def self.create(ctype, options)
      require 'zeevex_cluster/strategy/' + ctype.downcase
      clazz = self.const_get(ctype.capitalize)
      raise ArgumentError, "Unknown strategy type: #{ctype}" unless clazz
      clazz.new options
    end
  end
end

require 'zeevex_cluster/strategy/base'
