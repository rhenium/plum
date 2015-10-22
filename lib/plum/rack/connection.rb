module Plum
  module Rack
    class Connection
      attr_reader :app, :sock, :plum

      def initialize(app, sock, logger)
        @app = app
        @sock = sock
        @logger = logger
      end

      def stop
        @sock.close # TODO: gracefully shutdown
      end

      def start
        Thread.new {
          begin
            @sock = @sock.accept if @sock.respond_to?(:accept) # SSLSocket
            @plum = setup_plum
            @plum.run
          rescue Errno::EPIPE, Errno::ECONNRESET => e
            @logger.debug("connection closed: #{e}")
          rescue StandardError => e
            @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
          end
        }
      end

      private
      def setup_plum
        plum = ::Plum::HTTPConnection.new(@sock)
        plum.on(:connection_error) { |ex| @logger.error(ex) }

        plum.on(:stream) do |stream|
          stream.on(:stream_error) { |ex| @logger.error(ex) }

          headers = data = nil
          stream.on(:open) {
            headers = nil
            data = "".b
          }

          stream.on(:headers) { |h|
            @logger.debug("headers: " + h.map {|name, value| "#{name}: #{value}" }.join(" // "))
            headers = h
          }

          stream.on(:data) { |d|
            @logger.debug("data: #{d.bytesize}")
            data << d # TODO: store to file?
          }

          stream.on(:end_stream) {
            env = new_env(headers, data)
            r_headers, r_body = new_resp(@app.call(env))

            if r_body.is_a?(::Rack::BodyProxy)
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

        plum
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
        cauthority = headers.delete(":authority")
        cscheme = headers.delete(":scheme")
        ebase = {
          "REQUEST_METHOD"    => cmethod,
          "SCRIPT_NAME"       => "",
          "PATH_INFO"         => cpath_name,
          "QUERY_STRING"      => cpath_query.to_s,
          "SERVER_NAME"       => cauthority.split(":").first,
          "SERVER_PORT"       => (cauthority.split(":").last || 443), # TODO: forwarded header (RFC 7239)
        }

        headers.each {|key, value|
          ebase["HTTP_" + key.gsub("-", "_").upcase] = value
        }

        ebase.merge!({
          "rack.version"      => ::Rack::VERSION,
          "rack.url_scheme"   => cscheme,
          "rack.input"        => StringIO.new(data),
          "rack.errors"       => $stderr,
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
          "server" => "plum/#{::Plum::VERSION}",
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
    end
  end
end
