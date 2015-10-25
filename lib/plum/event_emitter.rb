module Plum
  module EventEmitter
    # Registers an event handler to specified event. An event can have multiple handlers.
    # @param name [String] The name of event.
    # @yield Gives event-specific parameters.
    def on(name, &blk)
      callbacks[name] << blk
    end

    def callback(name, *args)
      callbacks[name].each {|cb| cb.call(*args) }
    end

    private
    def callbacks
      @callbacks ||= Hash.new {|hash, key| hash[key] = [] }
    end
  end
end
