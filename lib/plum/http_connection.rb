module Plum
  class HTTPConnection < Connection
    def initialize(io, local_settings = {})
      super
    end

    private
    def negotiate!
      if @buffer.bytesize >= 4
        if CLIENT_CONNECTION_PREFACE.start_with?(@buffer)
          negotiate_with_knowledge
        else
          negotiate_with_upgrade
        end
      end
      # next
    end

    def negotiate_with_knowledge
      if @buffer.bytesize >= 24
        if @buffer.byteshift(24) == CLIENT_CONNECTION_PREFACE
          @state = :waiting_settings
          settings(@local_settings)
        end
      end
      # next
    end

    def negotiate_with_upgrade
      raise NotImplementedError, "Parsing HTTP/1.1 is hard..."
    end
  end
end
