module Plum
  module Rack
    class Config
      DEFAULT_CONFIG = {
        listeners: [],
        debug: false,
        log: nil, # $stdout
        server_push: true,
        threadpool_size: 1,
      }.freeze

      def initialize(config = {})
        @config = DEFAULT_CONFIG.merge(config)
      end

      def [](key)
        @config[key]
      end

      def []=(key, value)
        @config[key] = value
      end

      def to_s
        @config.to_s
      end
    end
  end
end
