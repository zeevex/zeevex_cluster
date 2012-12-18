require 'json'
require 'json/add/core'
require 'date'

require 'zeevex_cluster/serializer'

class ZeevexCluster::Serializer::JsonHash
  def new(options = {})
    @options = options
  end

  def is_time_field(key, val = nil)
    key.to_s.match(/(_at|timestamp)$/)
  end

  def untranslate_hash(parsed)
    raise ArgumentError, 'Must be a hash' unless parsed.is_a?(Hash)
    if parsed.count == 1 && parsed.has_key?('$primitive')
      return parsed['$primitive']
    end
    hash = {}
    parsed.each do |(key, val)|
      # val = Time.at(val).utc if is_time_field(key, val)
      hash[key.to_sym] = val
    end
    hash
  end

  def translate_hash(hash)
    raise ArgumentError, 'Must be a hash' unless hash.is_a?(Hash)
    hash = hash.clone
    #hash.keys.each do |key|
    #  hash[key] = hash[key].utc.to_f if is_time_field(key, hash[key])
    #end
    hash
  end

  def deserialize(str)
    parsed = JSON.parse(str, :symbolize_names => true, :object_class => IndifferentHash)
    case parsed
      when Hash then untranslate_hash(parsed)
      else parsed
    end
  end

  def serialize(obj)
    obj = case obj
            when Hash then translate_hash(obj)
            when Numeric, String, TrueClass, FalseClass, NilClass then
                  {'$primitive' => obj}
            else obj
          end
    JSON.dump(obj)
  end

  class IndifferentHash < Hash
    def fetch(key, defaultval = nil)
      super(key.to_sym, defaultval)
    end

    def [](key)
      super(key.to_sym)
    end
  end
end
