module ZeevexCluster
  module Logging
    def logger
      @logger || ZeevexCluster.logger
    end
  end

  module Util
    include Logging
  end

  module Hooks
    include Logging

    def add_hook_observer(observer)
      @hook_observers ||= []
      @hook_observers << observer
    end

    def add_hook(hook_name, observer)
      @hooks ||= []
      @hooks[hook_name] ||= []
      @hooks[hook_name] << observer
    end

    #
    # Takes a hash of hook_name_symbol => hooklist
    # hooklist can be a single proc or array of procs
    #
    def add_hooks(hookmap)
      hookmap.each do |(name, val)|
        Array(val).each do |hook|
          add_hook name, hook
        end
      end
    end

    def run_hook(hook_name, *args)
      logger.debug "<running hook #{hook_name}(#{args.inspect})>"
      if @hooks[hook_name]
        Array(@hooks[hook_name]).each do |hook|
          hook.call(self, *args)
        end
      end
      Array(@hook_observers).each do |observer|
        observer.call(hook_name, *args)
      end
    end
  end
end
