require 'json'
require 'date'

require 'zeevex_cluster/serializer'

class ZeevexCluster::Serializer::JsonHash
  def new(options = {})
    @options = options
  end

  def is_time_field(key, val = nil)
    key.to_s.match(/(_at|timestamp)$/)
  end

  def deserialize(str)
    return nil if str.nil? || str.empty?
    parsed = JSON.parse str
    raise ArgumentError, 'Must be a JSON serialized hash' unless parsed.is_a?(Hash)
    hash = {}
    parsed.each do |(key, val)|
      val = Time.at(val).utc if is_time_field(key, val)
      hash[key.to_sym] = val
    end
    hash
  end

  def serialize(hash)
    raise ArgumentError, 'Must be a hash' unless hash.is_a?(Hash)
    hash = hash.clone
    hash.keys.each do |key|
      hash[key] = hash[key].utc.to_f if is_time_field(key, hash[key])
    end
    hash.to_json
  end
end
