module ZeevexCluster::Coordinator
  class Memcached
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
    end

    def add(key, value, options = {})
      @client.add(to_key(key), value, options.fetch(:expiration, @expiration)) == 'STORED'
    end

    def set(key, value, options = {})
      @client.set(to_key(key), value, options.fetch(:expiration, @expiration)) == 'STORED'
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
      puts "client cas is #{res.inspect}"
      case res
        when nil then nil
        when "EXISTS\r\n", "EXISTS" then false
        when "STORED\r\n", "STORED" then true
      end
    rescue ZeevexCluster::Coordinator::DontChange => e
      false
    end

    def get(key)
      @client.get(to_key key)
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
