require 'zeevex_cluster/serializer'

module ZeevexCluster
  class Message < Hash

    include ZeevexCluster::Serializer

    REQUIRED_KEYS  = %w{source sequence sent_at expires_at contents content_type}.
        map {|x| x.to_sym}
    ALLOWED_KEYS   = %w{vclock options flags encoding}.
        map {|x| x.to_sym}
    FORBIDDEN_KEYS = ['$primitive', '$type', '$encoding']

    ALL_KEYS = REQUIRED_KEYS + ALLOWED_KEYS

    def initialize(hash)
      super()
      hash.keys.each do |x|
        raise ArgumentError, 'Only symbol keys are allowed in Messages' unless x.is_a?(Symbol)
      end
      self.merge! :content_type => 'application/json'
      self.merge! hash
    end

    def valid?
      vkeys = self.keys
      (REQUIRED_KEYS - vkeys).empty? &&
          (FORBIDDEN_KEYS & vkeys).empty?
    end

    def respond_to?(meth)
      if ALL_KEYS.include?(meth.to_s.chomp('=').to_sym)
        true
      else
        super
      end
    end

    protected

    def method_missing(meth, *args, &block)
      if ALL_KEYS.include?(meth.to_sym)
        self[meth]
      elsif ALL_KEYS.include?(key = meth.to_s.chomp('=').to_sym)
        self[key] = args[0]
      else
        super
      end
    end

  end
end
