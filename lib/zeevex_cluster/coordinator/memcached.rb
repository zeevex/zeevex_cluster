require 'zeevex_cluster/coordinator/base_key_val_store'

module ZeevexCluster::Coordinator
  class Memcached < BaseKeyValStore
    def self.setup
      unless @setup
        require 'memcache'
        BaseKeyValStore.setup

        @setup = true
      end
    end

    def initialize(options = {})
      super
      @client ||= MemCache.new "#{@server}:#{@port}"
    end

    def add(key, value, options = {})
      @client.add(to_key(key), serialize_token(value), options.fetch(:expiration, @expiration), raw?).chomp == 'STORED'
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    def set(key, value, options = {})
      @client.set(to_key(key), serialize_token(value), options.fetch(:expiration, @expiration), raw?).chomp == 'STORED'
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    #
    # Block is passed the current value, and returns the updated value.
    #
    # Block can raise DontChange to simply exit the block without updating.
    #
    # returns nil for no value
    # returns false for failure (somebody else set)
    # returns true for success
    #
    def cas(key, options = {}, &block)
      res = @client.cas(to_key(key), options.fetch(:expiration, @expiration), raw?) do |inval|
        serialize_token(yield(deserialize_token(inval)))
      end
      case res
        when nil then nil
        when "EXISTS\r\n", "EXISTS" then false
        when "STORED\r\n", "STORED" then true
      end
    rescue ZeevexCluster::Coordinator::DontChange => e
      false
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    def get(key)
      val = @client.get(to_key(key), raw?)
      val ? deserialize_token(val) : val
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    protected

    def raw?
      true
    end
  end
end
