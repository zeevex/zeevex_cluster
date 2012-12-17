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
      @client ||= MemCache.new "#@server:#@port"
    end

    def add(key, value, options = {})
      status( @client.add(to_key(key), serialize_value(value, options[:raw]),
                          options.fetch(:expiration, @expiration), raw?) ) == STORED
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def set(key, value, options = {})
      status( @client.set(to_key(key), serialize_value(value, options[:raw]),
                          options.fetch(:expiration, @expiration), raw?) ) == STORED
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
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
        serialize_value(yield(deserialize_value(inval, options[:raw])), options[:raw])
      end
      case status(res)
        when nil then nil
        when EXISTS then false
        when STORED then true
        else raise "Unhandled status code: #{res}"
      end
    rescue ZeevexCluster::Coordinator::DontChange
      false
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def get(key, options = {})
      val = @client.get(to_key(key), raw?)
      if val && !options[:raw]
        deserialize_value(val)
      else
        val
      end
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def append(key, val, options = {})
      val = serialize_value(val, options[:raw])
      key = to_key(key)
      status( @client.append(key, val) ) == STORED  ||
          status( @client.add(key, val, options.fetch(:expiration, @expiration), true) ) == STORED ||
          status( @client.append(key, val) ) == STORED
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def prepend(key, val, options = {})
      val = serialize_value(val, options[:raw])
      key = to_key(key)
      status( @client.prepend(key, val) ) == STORED  ||
          status( @client.add(key, val, options.fetch(:expiration, @expiration), true) ) == STORED ||
          status( @client.prepend(key, val) ) == STORED
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def push_to_queue(key, object, options = {})

    end

    protected

    STORED     = 'STORED'
    EXISTS     = 'EXISTS'
    NOT_STORED = 'NOT_STORED'
    NOT_FOUND  = 'NOT_FOUND'

    def status(response)
      case response
        when nil, true, false then response
        when String then response.chomp
        else
          raise ArgumentError, "This should only be called on results from cas, add, set, etc. - got result #{response.inspect}"
      end
    end

    def raw?
      true
    end
  end
end
