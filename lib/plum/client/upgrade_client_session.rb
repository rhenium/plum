# frozen-string-literal: true

module Plum
  # Try upgrade to HTTP/2
  class UpgradeClientSession
    def initialize(socket, config)
      prepare_session(socket, config)
    end

    def succ
      @session.succ
    end

    def empty?
      @session.empty?
    end

    def close
      @session.close
    end

    def request(headers, body, options, &headers_cb)
      @session.request(headers, body, options, &headers_cb)
    end

    private
    def prepare_session(socket, config)
      lcs = LegacyClientSession.new(socket, config)
      opt_res = lcs.request({ ":method" => "OPTIONS",
                              ":path" => "*",
                              "User-Agent" => config[:user_agent],
                              "Connection" => "Upgrade, HTTP2-Settings",
                              "Upgrade" => "h2c",
                              "HTTP2-Settings" => "" }, nil, {})
      lcs.succ until opt_res.finished?

      if opt_res.status == "101"
        lcs.close
        @session = ClientSession.new(socket, config)
        @session.plum.stream(1).set_state(:half_closed_local)
      else
        @session = lcs
      end
    end
  end
end

