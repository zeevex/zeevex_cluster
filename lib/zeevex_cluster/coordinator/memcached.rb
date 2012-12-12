module ZeevexCluster::Coordinator
  class Memcached
    include ZeevexCluster::Util

    def self.setup
      unless @setup
        require 'memcache'
        @setup = true
      end
    end

    def initialize(options = {})
      self.class.setup
      @options    = options
      if (!options[:server] && !options[:client]) || !options[:expiration]
        raise ArgumentError, "Must supply [:server or :client] and :expiration"
      end
      if options[:client]
        @client = options[:client]
      else
        @server = options[:server]
        @port   = options[:port] || 11211
        @client = MemCache.new "#{@server}:#{@port}"
      end
      @expiration = options[:expiration] || 60

      @logger     = options[:logger]

      @retries    = options.fetch(:retries,    20)
      @retry_wait = options.fetch(:retry_wait,  2)
      @retry_bo   = options.fetch(:retry_bo,    1.5)
    end

    [:add, :set, :cas, :get].each do |name|
      define_method "#{name}_with_retry", lambda { |*args, &block|
        with_connection_retry name, {}, *args, &block
      }
    end

    def with_connection_retry(method, options = {}, *args, &block)
      retry_left = options.fetch(:retries, @retries)
      retry_wait = options.fetch(:retry_wait, @retry_wait)
      begin
        send "do_#{method}", *args, &block
      rescue ZeevexCluster::Coordinator::ConnectionError
        if retry_left > 0
          logger.debug "retrying after #{retry_wait} seconds"
          retry_left -= 1
          sleep retry_wait
          retry_wait = retry_wait * options.fetch('retry_bo', @retry_bo)
          retry
        else
          logger.error 'Ran out of connection retries, re-raising'
          raise
        end
      end
    end

    def add(key, value, options = {})
      @client.add(to_key(key), value, options.fetch(:expiration, @expiration)).chomp == 'STORED'
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    def set(key, value, options = {})
      @client.set(to_key(key), value, options.fetch(:expiration, @expiration)).chomp == 'STORED'
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
      res = @client.cas(to_key(key), options.fetch(:expiration, @expiration), &block)
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
      @client.get(to_key key)
    rescue MemCache::MemCacheError
      raise ZeevexCluster::Coordinator::ConnectionError.new "Connection error", $!
    end

    protected

    def to_key(key)
      if @options[:namespace]
        "#{@options[:namespace]}:#{key}"
      elsif @options[:to_key_proc]
        @options[:to_key_proc].call(key)
      else
        key.to_s
      end
    end
  end
end
