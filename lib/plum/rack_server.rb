require "stringio"
require "rack"
require "plum"

module Plum
  class RackServer
    def initialize(app, options)
      @app = app
      @host = options[:Host].to_s
      @port = Integer(options[:Port])
      @debug = !!options[:Debug]
      @estream = $stderr
      @ostream = $stdout
    end

    def error(s)
      if s.is_a?(Exception)
        @estream.puts s
        @estream.puts s.backtrace
      else
        @estream.puts s
      end
    end

    def debug(s)
      if @debug
        @ostream.puts s
      end
    end

    def start
      @tcp_server = ::TCPServer.new(@host, @port)

      while @tcp_server && !@tcp_server.closed?
        begin
          sock = @tcp_server.accept
          id = sock.fileno
          debug("#{id}: accept!")
        rescue => e
          error(e)
          next
        end

        plum = Plum::HTTPConnection.new(sock)
        plum.on(:connection_error) { |ex| error(ex) }

        plum.on(:stream) do |stream|
          stream.on(:stream_error) { |ex| error(ex) }

          headers = data = nil
          stream.on(:open) {
            headers = nil
            data = "".b
          }

          stream.on(:headers) { |h|
            debug("headers: " + h.map {|name, value| "#{name}: #{value}" }.join(" // "))
            headers = h
          }

          stream.on(:data) { |d|
            debug("data: #{d.bytesize}")
            data << d
          }

          stream.on(:end_stream) {
            env = new_env(headers, data)
            r_headers, r_body = new_resp(@app.call(env))

            if r_body.is_a?(Rack::BodyProxy)
              stream.respond(r_headers, end_stream: false)
              r_body.each { |part|
                stream.send_data(part, end_stream: false)
              }
              stream.send_data(nil)
            else
              stream.respond(r_headers, r_body)
            end
          }
        end

        Thread.new {
          begin
            plum.run
          rescue
            p $!
            puts $!.backtrace
          end
        }
      end
    end

    def new_env(h, data)
      headers = h.group_by { |k, v| k }.map { |k, kvs|
        if k == "cookie"
          [k, kvs.map(&:last).join("; ")]
        else
          [k, kvs.first.last]
        end
      }.to_h

      cmethod = headers.delete(":method")
      cpath = headers.delete(":path")
      cpath_name, cpath_query = cpath.split("?", 2).map(&:to_s)
      cauthority = headers.delete(":authority") # is not empty
      cscheme = headers.delete(":scheme")
      ebase = {
        "REQUEST_METHOD"    => cmethod,
        "SCRIPT_NAME"       => cpath_name == "/" ? "" : cpath_name,
        "PATH_INFO"         => cpath,
        "QUERY_STRING"      => cpath_query,
        "SERVER_NAME"       => cauthority.split(":").first,
        "SERVER_POST"       => @port.to_s,
      }

      headers.each {|key, value|
        ebase["HTTP_" + key.gsub("-", "_").upcase] = value
      }

      ebase.merge!({
        "rack.version"      => Rack::VERSION,
        "rack.url_scheme"   => cscheme,
        "rack.input"        => StringIO.new(data),
        "rack.errors"       => @estream,
        "rack.multithread"  => true,
        "rack.multiprocess" => false,
        "rack.run_once"     => false,
        "rack.hijack?"      => false,
      })

      ebase
    end

    def new_resp(app_call)
      r_status, r_h, r_body = app_call

      rbase = {
        ":status" => r_status,
        "server" => "plum/#{Plum::VERSION}",
      }

      r_h.each do |key, v_|
        if key.start_with?("rack.")
          next
        end

        key = key.downcase.gsub(/^x-/, "")
        vs = v_.split("\n")
        if key == "set-cookie"
          rbase[key] = vs.join("; ") # RFC 7540 8.1.2.5
        else
          rbase[key] = vs.join(",") # RFC 7230 7
        end
      end

      [rbase, r_body]
    end

    def stop
      @tcp_server.close if @tcp_server
    end
  end
end
