class ZeevexCluster::Util::Future
  def initialize(computation)
    @computation = computation
    @mutex       = Mutex.new
    @queue       = Queue.new
    @exception   = nil
    @done        = false
    @result      = false
    @executed    = false
  end

  #
  # not MT-safe; only to be called from executor thread
  #
  def execute
    @executed = true
    @queue << @computation.call
  rescue Exception
    @exception = $!
    @queue    << $!
  end

  def call
    execute
  end

  def exception
    @mutex.synchronize do
      @exception
    end
  end

  def exception?
    !! @exception
  end

  def value(reraise = true)
    @mutex.synchronize do
      unless @done
        @done   = true
        @result = @queue.pop
      end
      if @exception && reraise
        raise @exception
      else
        @result
      end
    end
  end

  def ready?
    @mutex.synchronize do
      ! @done && ! @queue.empty?
    end
  end

  def set_result(&block)
    @mutex.synchronize do
      raise ArgumentError, "Must supply block" unless block_given?
      raise ArgumentError, "Already supplied block" if @computation
      raise ArgumentError, "Future already executed" if @done

      @computation = block
      execute
    end
  end

  #def wait(timeout = nil)
  #  @queue.wait timeout
  #end
end
