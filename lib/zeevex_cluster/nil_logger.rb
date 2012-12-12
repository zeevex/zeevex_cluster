module ZeevexCluster
  class NilLogger
    def method_missing(symbol, *args)
      nil
    end
  end
end
