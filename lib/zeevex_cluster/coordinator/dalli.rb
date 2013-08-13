require 'zeevex_cluster/coordinator/base_key_val_store'

module ZeevexCluster::Coordinator
  class Dalli < BaseKeyValStore
    def self.setup
      unless @setup
        require 'dalli'
        BaseKeyValStore.setup

        @setup = true
      end
    end

    def initialize(options = {})
      super
      @client ||= ::Dalli::Client.new "#@server:#@port"
    end

    def add(key, value, options = {})
      @client.add(to_key(key), serialize_value(value, options[:raw]),
                  options.fetch(:expiration, @expiration), raw: raw?)
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def set(key, value, options = {})
      @client.set(to_key(key), serialize_value(value, options[:raw]),
                  options.fetch(:expiration, @expiration), raw: raw?)
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def delete(key, options = {})
      @client.delete(to_key(key))
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
      res = @client.cas(to_key(key), options.fetch(:expiration, @expiration), raw: raw?) do |inval|
        serialize_value(yield(deserialize_value(inval, options[:raw])), options[:raw])
      end
      case res
        when nil then nil
        when false then false
        when true then true
        else raise "Unhandled status code: #{res}"
      end
    rescue ZeevexCluster::Coordinator::DontChange
      false
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def get(key, options = {})
      val = @client.get(to_key(key), raw: raw?)
      if val && !options[:raw]
        deserialize_value(val)
      else
        val
      end
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def append(key, val, options = {})
      val = serialize_value(val, options[:raw])
      key = to_key(key)
      @client.append(key, val)   ||
        @client.add(key, val, options.fetch(:expiration, @expiration), raw: true) ||
        @client.append(key, val)
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def prepend(key, val, options = {})
      val = serialize_value(val, options[:raw])
      key = to_key(key)
      @client.prepend(key, val)  ||
        @client.add(key, val, options.fetch(:expiration, @expiration), raw: true) ||
        @client.prepend(key, val)
    rescue ::Dalli::DalliError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def push_to_queue(key, object, options = {})

    end

    protected

    def raw?
      true
    end
  end
end
