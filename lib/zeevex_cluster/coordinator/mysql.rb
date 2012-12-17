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
      @logger = @options[:logger] || Logger.new(STDOUT)
      @namespace = @options.fetch(:namespace, '')
      @client ||= Mysql2::Client.new(:host => options[:server] || 'localhost',
                                     :port => options[:port] | 3306,
                                     :database => options[:database] || 'zcluster',
                                     :username => options[:username],
                                     :password => options[:password],
                                     :reconnect => true,
                                     :symbolize_keys => true,
                                     :cache_rows => false,
                                     :application_timezone => :utc,
                                     :database_timezone => :utc)
    end

    # TODO: handle upsert when old row is expired
    def add(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, options[:raw])
      res = do_insert_row(:keyname => key, :value => value)
      res[:affected_rows] == 1
    rescue Mysql2::Error => e
      # duplicate key, probably
      case e.error_number
        # duplicate key
        when 1062
          false
        else raise "Unhandled mysql error: #{e.errno} #{e.message}"
      end
    rescue StandardError
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    def set(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, options[:raw])
      row = {:keyname => key, :value => value}
      row[:expires_at] = now + options[:expiration] if options[:expiration]
      res = do_upsert_row(row)
      res[:affected_rows] == 1
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

      orig_row = do_get_first(key, :ignore_expiration => true)
      return nil unless orig_row

      expiration = options.fetch(:expiration, @expiration)

      newval = serialize_value(yield(deserialize_value(orig_row[:value], options[:raw])), options[:raw])
      updates = {:value => newval}
      updates[:expires_at] = now + options[:expiration] if options[:expiration]
      res = do_update_row(simple_cond(orig_row), updates)
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
      row = do_get_first key
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
      res = query %{UPDATE #@table set value = CONCAT(value, #{qval value}),
                      lock_version = lock_version + 1,
                      updated_at = #{qnow}
                      where #{qcol keyname} = #{qval key};}
      res[:affected_rows] == 1
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    # TODO
    def prepend(key, val, options = {})
      res = query %{UPDATE #@table set value = CONCAT(#{qval value}, value),
                      lock_version = lock_version + 1,
                      updated_at = #{qnow}
                      where #{qcol keyname} = #{qval key};}
      res[:affected_rows] == 1
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    protected

    # mysql get
    def do_get(key, options = {})
      conditions = []
      conditions << %{#{qcol 'keyname'} = #{qval key}}
      conditions << %{#{qcol 'namespace'} = #{qval @namespace}}
      unless options[:ignore_expiration]
        conditions << %{(#{qcol 'expires_at'} IS NULL or #{qcol 'expires_at'} < #{qnow})}
      end
      query(%{SELECT * from #@table where #{conditions.join(' AND ')};})[:resultset]
    end

    def do_get_first(*args)
      res = do_get(*args)
      res && res.first
    end

    def simple_cond(row)
      slice_hash row, :keyname, :lock_version
    end

    def make_comparison(trip)
      trip = case trip.count
               when 1 then [trip[0], "IS NOT", nil]
               when 2 then [trip[0], "=", trip[1]]
               when 3 then trip
               else raise "Must have 1-3 arguments"
             end
      %{#{qcol trip[0]} #{trip[1]} #{qval trip[2]}}
    end

    def make_conditions(cond)
      case cond
        when String then cond
        when Array then cond.map {|trip| make_comparison(trip) }.join(" AND ")
        when Hash then cond.map {|(k,v)| make_comparison([k, v].flatten) }.join(" AND ")
        else raise "Unknown condition format: #{cond.inspect}"
      end
    end

    def do_insert_row(row, options = {})
      (quals[:keyname] && quals[:value]) or raise ArgumentError, "Must specify at least key and value"
      quals[:namespace] = @namespace
      now = self.now
      row = {:created_at => now, :updated_at => now}.merge(row) unless options[:skip_timestamps]
      query %{INSERT INTO #@table (#{row.keys.map {|k| qcol(k)}.join(", ")})
                           values (#{row.values.map {|k| qval(k)}.join(", ")});}
    end

    def do_upsert_row(row, options = {})
      (row[:keyname] && row[:value]) or raise ArgumentError, "Must specify at least key and value"
      now = self.now
      row = row.merge(:namespace => @namespace)
      row = {:created_at => now, :updated_at => now}.merge(row) unless options[:skip_timestamps]
      updatable_row = trim_hash(row, [:created_at, :keyname, :lock_version]).merge(
          :lock_version => Literal.new("lock_version + 1"))
      query %{INSERT INTO #@table (#{row.keys.map {|k| qcol(k)}.join(", ")})
                           values (#{row.values.map {|k| qval(k)}.join(", ")})
              ON DUPLICATE KEY UPDATE lock_version = lock_version + 1,
                              #{updatable_row.map {|(k,v)| "#{qcol k} = #{qval v}"}.join(", ")};}
    end

    def do_update_row(quals, newattrvals, options = {})
      quals[:keyname] or raise "Must specify at least the key in an update"
      conditions = "WHERE " + make_conditions(quals)
      newattrvals = {:updated_at => now}.merge(newattrvals) unless options[:skip_timestamps]
      newattrvals = newattrvals.merge(:namespace => @namespace, :lock_version => Literal.new("lock_version + 1"))
      updates = newattrvals.map do |(key, val)|
        "#{qcol key} = #{qval val}"
      end
      statement = %{UPDATE #@table SET #{updates.join(", ")} #{conditions};}
      res = query statement
      res[:affected_rows] == 0 ? false : true
    end

    def clear_expired_rows
      @client.query %{DELETE FROM #@table WHERE #{qcol 'expires_at'} < #{qnow} and #{qcol 'namespace'} = #{qval @namespace};}
    rescue
      logger.error "Error clearing expired rows: #{$!.inspect} #{$!.message}"
    end

    def query(statement, options = {})
      unless options[:ignore_expiration]
        clear_expired_rows
      end
      logger.debug "STMT = [#{statement}]"
      res = @client.query statement, options
      {:resultset => res, :affected_rows => @client.affected_rows, :last_id => @client.last_id}
    rescue
      logger.error %{MYSQL connection error: #{$!.inspect}:\nstatement=[#{statement}]\n#{$!.backtrace.join("\n")}}
      raise
    end

    #
    # extract a hash with a subset of keys
    #
    def slice_hash(src, *keys)
      hash = src.class.new
      Array(keys).flatten.each { |k| hash[k] = src[k] if src.has_key?(k) }
      hash
    end

    def trim_hash(src, *keys)
      hash = src.class.new
      keys = Array(keys).flatten
      src.keys.each { |k| hash[k] = src[k] unless keys.include?(k) }
      hash
    end

    # FIXME
    def qcol(colname)
      %{#{colname}}
    end

    # FIXME
    def qval(val)
      case val
        when Literal then val
        when String then %{'#{val}'}
        when true then '1'
        when false then '0'
        when nil then 'NULL'
        when Numeric then val.to_s
        when Time then qval(val.utc.strftime('%Y-%m-%d-%H:%M:%S'))
        else val
      end
    end

    def qnow
      qval now
    end

    def now
      Time.now.utc
    end

    class Literal < String; end
  end
end
