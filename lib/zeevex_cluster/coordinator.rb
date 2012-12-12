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
  end
end

