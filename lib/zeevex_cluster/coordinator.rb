module ZeevexCluster
  module Coordinator
    # flow control exceptions used in these classes
    class DontChange < StandardError; end

    # errors throw by these classes
    class CoordinatorError < StandardError
      attr_accessor :chained
      def initialize(message, original = nil)
        @chained = original
        super(message)
      end
      def to_s
        @chained ? super + "; chained = #{@chained.inspect}" : super
      end
    end

    class ConnectionError < CoordinatorError; end
    class ConsistencyError < CoordinatorError; end

    def self.create(coordinator_type, options)
      require 'zeevex_cluster/coordinator/' + coordinator_type
      clazz = self.const_get(coordinator_type.capitalize)
      raise ArgumentError, "Unknown coordinator type: #{coordinator_type}" unless clazz
      ZeevexCluster.Synchronized(clazz.new(options))
    end
  end
end

