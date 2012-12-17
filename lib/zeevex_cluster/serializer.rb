
module ZeevexCluster
  module Serializer
    def included(base)
      base.extend(ClassMethods)
      base.class_eval { include ZeevexCluster::Serializer::InstanceMethods }
    end

    module InstanceMethods
      def to_json
        serializer.serialize(self)
      end

      def serializer
        @_serializer ||= ZeevexCluster::Serializer::JsonHash.new
      end
    end

    module ClassMethods
      def from_json(string)
        serializer.deserialize(self)
      end
    end
  end
end

require 'zeevex_cluster/serializer/json_hash'
