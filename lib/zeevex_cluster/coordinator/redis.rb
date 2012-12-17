require 'zeevex_cluster/coordinator/base_key_val_store'

module ZeevexCluster::Coordinator
  class Redis < BaseKeyValStore
    def self.setup
      unless @setup
        require 'redis'
        BaseKeyValStore.setup
        @setup = true
      end
    end

    def initialize(options = {})
      super
      @client ||= ::Redis.new :host => @server, :port => @port
    end

    def add(key, value, options = {})
      if @client.setnx(to_key(key), serialize_value(value, options[:raw]))
        @client.expire to_key(key), options.fetch(:expiration, @expiration)
        true
      else
        false
      end
    rescue ::Redis::CannotConnectError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def set(key, value, options = {})
      status( @client.setex(to_key(key),
                            options.fetch(:expiration, @expiration),
                            serialize_value(value, options[:raw])) ) == STATUS_OK
    rescue ::Redis::CannotConnectError
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
    def cas(key, options = {})
      key = to_key(key)
      @client.unwatch
      @client.watch key
      orig_val = @client.get key
      return nil if orig_val.nil?

      expiration = options.fetch(:expiration, @expiration)

      newval = serialize_value(yield(deserialize_value(orig_val, options[:raw])), options[:raw])
      res = @client.multi do
        if expiration
          @client.setex key, expiration, newval
        else
          @client.set key, newval
        end
      end
      @client.unwatch
      case res
        when nil then false
        when Array then true
        else raise "Unhandled return value from multi - #{res.inspect}"
      end
    rescue ZeevexCluster::Coordinator::DontChange => e
      false
    rescue ::Redis::CannotConnectError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def get(key)
      deserialize_value(@client.get(to_key(key)), options[:raw])
    rescue ::Redis::CannotConnectError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    protected

    STATUS_OK = 'OK'

    def status(response)
      case response
        when nil then nil
        when String then response.chomp
        else
          raise ArgumentError, 'This should only be called on results from set / setex, etc.'
      end
    end

  end
end
