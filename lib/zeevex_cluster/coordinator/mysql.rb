require 'zeevex_cluster/coordinator/base_key_val_store'

#
# example setup for mysql coordinator:
#
# grant all privileges on zcluster.* to 'zcluster'@localhost identified by 'zclusterp';
#
# drop table kvstore;
#
# create table kvstore (keyname varchar(255) not null,
#                      value mediumtext,
#                      namespace varchar(255) default '',
#                      flags integer default 0,
#                      created_at datetime,
#                      expires_at datetime,
#                      updated_at datetime,
#                      lock_version integer default 0);
#
# create unique index keyname_idx on kvstore (keyname, namespace);
#

#
# expired key handling hasn't been well-tested
#
module ZeevexCluster::Coordinator
  class Mysql < BaseKeyValStore
    ERR_DUPLICATE_KEY = 1062

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

    #
    # Add the value for a key to the DB if there is no existing entry
    # Serializes unless :raw => true
    #
    # Returns true if key was added, false if key already had a value
    #
    def add(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, is_raw?(options))
      res = do_insert_row({:keyname => key, :value => value, :namespace => @namespace},
                           :expiration => options.fetch(:expiration, @expiration))
      res[:affected_rows] == 1
    rescue Mysql2::Error => e
      case e.error_number
        # duplicate key
        # see http://www.briandunning.com/error-codes/?source=MySQL
        when ERR_DUPLICATE_KEY
          false
        else
          raise  ZeevexCluster::Coordinator::ConnectionError.new, "Unhandled mysql error: #{e.errno} #{e.message}", e
      end
    rescue
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    #
    # Set the value for a key, serializing unless :raw => true
    #
    def set(key, value, options = {})
      key = to_key(key)
      value = serialize_value(value, is_raw?(options))
      row = {:keyname => key, :value => value}

      res = do_upsert_row(row, :expiration => options.fetch(:expiration, @expiration), :skip_locking => true)
      res[:success]
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    #
    # Delete key from database; true if key existed beforehand
    #
    def delete(key, options = {})
      res = do_delete_row(:keyname => to_key(key))
      res[:success]
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

      orig_row = do_get_first(key)
      return nil unless orig_row

      expiration = options.fetch(:expiration, @expiration)

      newval = serialize_value(yield(deserialize_value(orig_row[:value], is_raw?(options))), is_raw?(options))
      updates = {:value => newval}
      res = do_update_row(simple_cond(orig_row), updates, :expiration => options.fetch(:expiration, @expiration))
      case res
        when false then false
        when true then true
        else
          raise ZeevexCluster::Coordinator::ConnectionError, "Unhandled return value from do_update_row - #{res.inspect}"
      end
    rescue ZeevexCluster::Coordinator::DontChange => e
      false
    rescue ::Mysql2::Error
      logger.error "got error in cas: #{$!.inspect}"
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    rescue
      logger.error "got general error in cas: #{$!.inspect}"
      raise
    end

    #
    # Fetch the value for a key, deserializing unless :raw => true
    #
    def get(key, options = {})
      key = to_key(key)
      row = do_get_first key
      return nil if row.nil?

      if !is_raw?(options)
        deserialize_value(row[:value])
      else
        row[:value]
      end
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    # append string vlaue to an entry
    # does NOT serialize
    def append(key, str, options = {})
      newval = Literal.new %{CONCAT(value, #{qval str})}
      do_update_row({:keyname => to_key(key)}, {:value => newval})
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    # prepend string value to an entry
    # does NOT serialize
    def prepend(key, str, options = {})
      newval = Literal.new %{CONCAT(#{qval str}, value)}
      do_update_row({:keyname => to_key(key)}, {:value => newval})
    rescue ::Mysql2::Error
      raise ZeevexCluster::Coordinator::ConnectionError.new 'Connection error', $!
    end

    protected

    # mysql get wrapper. returns just the resultset as a list of hashes
    # which may be nil or empty list if none matched.
    def do_get(key, options = {})
      conditions = []
      conditions << %{#{qcol 'keyname'} = #{qval key}}
      conditions << %{#{qcol 'namespace'} = #{qval @namespace}}
      query(%{SELECT * from #@table where #{conditions.join(' AND ')};})[:resultset]
    end

    def do_get_first(*args)
      res = do_get(*args)
      res && res.first
    end

    def simple_cond(row)
      slice_hash row, :namespace, :keyname, :lock_version
    end

    def make_comparison(trip)
      trip = case trip.count
               when 1 then [trip[0], 'IS NOT', nil]
               when 2 then [trip[0], '=', trip[1]]
               when 3 then trip
               else raise 'Must have 1-3 arguments'
             end
      %{#{qcol trip[0]} #{trip[1]} #{qval trip[2]}}
    end

    def make_row_conditions(cond)
      cond = {:namespace => @namespace}.merge(cond)
      make_conditions(cond)
    end

    def make_conditions(cond)
      case cond
        when String then cond
        when Array then cond.map {|trip| make_comparison(trip) }.join(' AND ')
        when Hash then cond.map {|(k,v)| make_comparison([k, v].flatten) }.join(' AND ')
        else raise "Unknown condition format: #{cond.inspect}"
      end
    end

    def do_insert_row(row, options = {})
      (row[:keyname] && row[:value]) or raise ArgumentError, 'Must specify at least key and value'
      now = self.now
      row = row.merge(:namespace => @namespace)
      row = {:created_at => now, :updated_at => now}.merge(row) unless options[:skip_timestamps]
      row = {:expires_at => now + options[:expiration]}.merge(row) if options[:expiration]
      res = query %{INSERT INTO #@table (#{row.keys.map {|k| qcol(k)}.join(', ')})
                           values (#{row.values.map {|k| qval(k)}.join(', ')});}
      res[:success] = (res[:affected_rows] == 1)
      res
    end

    def do_upsert_row(row, options = {})
      (row[:keyname] && row[:value]) or raise ArgumentError, 'Must specify at least key and value'
      now = self.now

      ## what values are set if the row is inserted
      row = row.merge(:namespace => @namespace)
      row = {:created_at => now, :updated_at => now}.merge(row) unless options[:skip_timestamps]
      row = {:expires_at => now + options[:expiration]}.merge(row)  if options[:expiration]

      ## values updated if row already exists
      # these columns shouldn't be set on update
      updatable_row = trim_hash(row, [:created_at, :keyname, :namespace, :lock_version])
      # update of a row should increment the lock version, rather than setting it
      updatable_row.merge!(:lock_version => Literal.new('lock_version + 1')) unless options[:skip_locking]

      res = query %{INSERT INTO #@table (#{row.keys.map {|k| qcol(k)}.join(', ')})
                           values (#{row.values.map {|k| qval(k)}.join(', ')})
              ON DUPLICATE KEY UPDATE
                              #{updatable_row.map {|(k,v)| "#{qcol k} = #{qval v}"}.join(', ')};}

      # see http://dev.mysql.com/doc/refman/5.0/en/insert-on-duplicate.html for WTF affected_rows
      # overloading
      res[:success] = [1,2].include?(res[:affected_rows])
      res[:upsert_type] = case res[:affected_rows]
                            when 1 then :insert
                            when 2 then :update
                            else :none
                          end
      res
    end

    #
    # note, unlike some of the do_* functions, returns a simple boolean for success
    #
    def do_update_row(quals, newattrvals, options = {})
      quals[:keyname] or raise 'Must specify at least the full key in an update'
      conditions = 'WHERE ' + make_row_conditions(quals)
      newattrvals = {:updated_at => now}.merge(newattrvals) unless options[:skip_timestamps]
      newattrvals = {:expires_at => now + options[:expiration]}.merge(newattrvals) if options[:expiration]
      newattrvals.merge!({:lock_version => Literal.new('lock_version + 1')}) unless options[:skip_locking]
      updates = newattrvals.map do |(key, val)|
        "#{qcol key} = #{qval val}"
      end
      statement = %{UPDATE #@table SET #{updates.join(', ')} #{conditions};}
      res = query statement
      res[:affected_rows] == 0 ? false : true
    end

    def do_delete_row(quals, options = {})
      quals[:keyname] or raise 'Must specify at least the key in a delete'
      conditions = 'WHERE ' + make_row_conditions(quals)
      statement = %{DELETE from #@table #{conditions};}
      res = query statement
      res[:success] = res[:affected_rows] > 0
      res
    end

    def clear_expired_rows
      statement = %{DELETE FROM #@table WHERE #{qcol 'expires_at'} < #{qnow} and #{qcol 'namespace'} = #{qval @namespace};}
      @client.query statement, _mysql_query_options
      true
    rescue ::Mysql2::Error
      log_exception($!, statement)
      false
    rescue
      logger.error %{Unhandled error in query: #{$!.inspect}\nstatement=[#{statement}]\n#{$!.backtrace.join("\n")}}
    end

    def _mysql_query_options
      {as: :hash, symbolize_keys: true}
    end

    #
    # chokepoint for *most* queries issued to MySQL, except the one from `clear_expired_rows` as we call it.
    #
    # returns a hash containing values returned from mysql2 API
    #
    def query(statement, options = {})
      options = _mysql_query_options.merge(options)
      unless options.delete(:ignore_expiration)
        clear_expired_rows
      end
      logger.debug "[#{statement}]"
      res = @client.query statement, options
      {:resultset => res, :affected_rows => @client.affected_rows, :last_id => @client.last_id}
    rescue ::Mysql2::Error
      log_exception($!, statement)
      raise
    rescue
      logger.error %{Unhandled error in query: #{$!.inspect}\nstatement=[#{statement}]\n#{$!.backtrace.join("\n")}}
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

    #
    # return a new hash with a set of keys removed
    #
    def trim_hash(src, *keys)
      hash = src.class.new
      keys = Array(keys).flatten
      src.keys.each { |k| hash[k] = src[k] unless keys.include?(k) }
      hash
    end

    def log_exception(e, statement=nil)
      logger.error %{Mysql exception errno=#{e.errno}, sql_state=#{e.sql_state}, message=#{e.message}, statement=[#{statement || 'UNKNOWN'}]\n#{e.backtrace.join("\n")}}
    end

    # quote quotes in a quotable string.
    def quote_string(s)
      s.gsub(/\\/, '\&\&').gsub(/'/, "''") # ' (for ruby-mode)
    end

    # quote a column name
    def qcol(colname)
      %{`#{colname}`}
    end

    # quote a value - takes the quoting/translation style from the Ruby type of the value itself
    # rather than the column definition as e.g. ActiveRecord might.
    def qval(val)
      case val
        when Literal then val
        when String then %{'#{quote_string val}'}
        when true then '1'
        when false then '0'
        when nil then 'NULL'
        when Bignum then val.to_s('F')
        when Numeric then val.to_s
        when Time then qval(val.utc.strftime('%Y-%m-%d-%H:%M:%S'))
        else val
      end
    end

    # quoted time value for now
    def qnow
      qval now
    end

    #
    # now, as a Time, in UTC
    #
    def now
      Time.now.utc
    end

    #
    # unlike the base implementation, we don't fold the namespace into the key
    # we leave that in a separate column
    #
    def to_key(key)
      if @options[:to_key_proc]
        @options[:to_key_proc].call(key)
      else
        key.to_s
      end
    end

    #
    # class used to indicate a value to be passed to MySQL unquoted; useful for
    # e.g. arithmetic expressions
    #
    class Literal < String; end
  end
end
