require 'zeevex_cluster/coordinator/base_key_val_store'

module ZeevexCluster::Coordinator
  class Mysql < BaseKeyValStore
    def self.setup
      unless @setup
        require 'mysql2'
        BaseKeyValStore.setup

        @setup = true
      end
    end

    def initialize(options = {})
      super
      @table = @options[:table] || 'kvstore'
      @client ||= Mysql2::Client.new(:host => options[:server] || 'localhost',
                                     :port => options[:port] | 3306,
                                     :database => options[:database] || 'zcluster',
                                     :username => options[:username],
                                     :password => options[:password],
                                     :reconnect => true)
    end

    # TODO: handle upsert when old row is expires
    def add(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, options[:raw])
      @client.query %{INSERT INTO #@table (keyname, value, created_at, lock_version)
                      values (#{qval key}, #{qval value}, #{now}, lock_version + 1);}
      @client.affected_rows == 1
    rescue Mysql2::Error => e
      # duplicate key, probably
      case e.error_number
        # duplicate key
        when 1062 then false
        else raise "Unhandled mysql error: #{e.errno} #{e.message}"
      end
    rescue StandardError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def set(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, options[:raw])
      @client.query %{INSERT INTO #@table (keyname, value, created_at)
                            values (#{qval key}, #{qval value}, #{now})
                           ON DUPLICATE KEY UPDATE value=#{qval value}, lock_version=lock_version + 1;}
      @client.affected_rows == 1
    rescue ::Mysql2::Error
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

      orig_row = do_get(key)
      return nil if orig_row.nil?

      expiration = options.fetch(:expiration, @expiration)

      newval = serialize_value(yield(deserialize_value(orig_row[:value], options[:raw])), options[:raw])
      res = do_update_row(orig_row, :value => newval)
      case res
        when false then false
        when true then true
        else raise "Unhandled return value from do_update_row - #{res.inspect}"
      end
    rescue ZeevexCluster::Coordinator::DontChange => e
      false
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end


    def get(key, options = {})
      key = to_key(key)
      row = do_get key
      return nil if row.nil?

      if !options[:raw]
        deserialize_value(row[:value])
      else
        row[:value]
      end
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def append(key, val, options = {})
      @client.query %{UPDATE #@table set value = CONCAT(value, #{qval value}),
                      lock_version = lock_version + 1
                      where #{qcol keyname} = #{qval key};}
      @client.affected_rows == 1
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    # TODO
    def prepend(key, val, options = {})
      @client.query %{UPDATE #@table set value = CONCAT(#{qval value}, value),
                      lock_version = lock_version + 1
                      where #{qcol keyname} = #{qval key};}
      @client.affected_rows == 1
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    protected

    # mysql get
    def do_get(key, options = {})
      conditions = []
      conditions << %{#{qcol 'keyname'} = #{qval key}}
      unless options[:ignore_expiration]
        conditions << %{(#{qcol 'expires_at'} IS NULL or #{qcol 'expires_at'} < NOW())}
      end
      res = @client.query %{SELECT * from #@table where #{conditions.join(' AND ')};},
                          :symbolize_keys => true
      res.count == 0 ? nil : res.first
    end

    # mysql get
    def do_update_row(row, newattrvals)
      key = row[:keyname]
      conditions = %{WHERE keyname = #{qval key} and lock_version = #{row[:lock_version]}}
      updates = newattrvals.map do |(key, val)|
        "#{qcol key} = #{qval val}"
      end
      updates << "lock_version = lock_version + 1"
      statement = %{UPDATE #@table SET #{updates.join(", ")} #{conditions};}
      puts "STMT = [#{statement}]"
      res = @client.query statement
      @client.affected_rows == 0 ? false : true
    end

    # FIXME
    def qcol(colname)
      %{#{colname}}
    end

    # FIXME
    def qval(val)
      case val
        when String then %{'#{val}'}
        when true then '1'
        when false then '0'
        when nil then 'NULL'
        when Numeric then val.to_s
        when Time then qval(val.utc.strftime('%Y-%m-%d-%H:%M:%S'))
        else val
      end
    end

    def now
      qval Time.now.utc
    end

  end
end
