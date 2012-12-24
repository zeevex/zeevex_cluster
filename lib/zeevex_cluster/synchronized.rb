# Alex's Ruby threading utilities - taken from https://github.com/alexdowad/showcase

require 'thread'

# Wraps an object, synchronizes all method calls
# The wrapped object can also be set and read out
#   which means this can also be used as a thread-safe reference
#   (like a 'volatile' variable in Java)
class ZeevexCluster::Synchronized
  def initialize(obj)
    @obj   = obj
    @mutex = Mutex.new
  end

  def _set_synchronized_object(val)
    @mutex.synchronize { @obj = val }
  end
  def _get_synchronized_object
    @mutex.synchronize { @obj }
  end

  [:class, :inspect, :to_s, :==, :hash, :equal?].each do |method|
    undef_method method
  end

  def class
    @obj.class
  end

  def respond_to?(method)
    if [:_set_synchronized_object, :_get_synchronized_object].include?(method.to_sym)
      true
    else
      @obj.respond_to?(method)
    end
  end

  def method_missing(method,*args,&block)
    result = @mutex.synchronize { @obj.send(method,*args,&block) }
    # some methods return "self" -- if so, return this wrapper
    result.object_id == @obj.object_id ? self : result
  end
end

#
# make object synchronized unless already synchronized
#
def ZeevexCluster.Synchronized(obj)
  if obj.respond_to?(:_get_synchronized_object)
    obj
  else
    ZeevexCluster::Synchronized.new(obj)
  end
end
