require 'zeevex_cluster/coordinator'

class ZeevexCluster::Coordinator::BaseKeyValStore
  include ZeevexCluster::Util

  def self.setup
    unless @setup
      require 'memcache'
      require 'zeevex_cluster/serializer/json_hash'
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
    end
    @expiration = options[:expiration] || 60

    @logger     = options[:logger]

    @serializer    = options[:serializer] || ZeevexCluster::Serializer::JsonHash.new

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

  protected

  def serialize_token(token)
    @serializer.serialize(token)
  end

  def deserialize_token(tokenstr)
    @serializer.deserialize(tokenstr)
  end

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
