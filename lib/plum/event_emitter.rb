# -*- frozen-string-literal: true -*-
module Plum
  module EventEmitter
    # Registers an event handler to specified event. An event can have multiple handlers.
    # @param name [Symbol] The name of event.
    # @yield Gives event-specific parameters.
    def on(name, &blk)
      ((@callbacks ||= {})[name] ||= []) << blk
    end

    # Invokes an event and call handlers with args.
    # @param name [Symbol] The identifier of event.
    def callback(name, *args)
      (@callbacks ||= {})[name]&.each { |cb| cb.call(*args) }
    end
  end
end
