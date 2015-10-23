module Plum
  module Rack
    class Connection
      attr_reader :app, :sock, :plum

      def initialize(app, plum, logger)
        @app = app
        @plum = plum
        @logger = logger

        setup_plum
      end

      def stop
        @plum.stop
      end

      def run
        begin
          @plum.run
        rescue Errno::EPIPE, Errno::ECONNRESET => e
          @logger.debug("connection closed: #{e}")
        rescue StandardError => e
          @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
        end
      end

      private
      def setup_plum
        @plum.on(:connection_error) { |ex| @logger.error(ex) }

        @plum.on(:stream) do |stream|
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
            handle_request(stream, headers, data)
          }
        end
      end

      def send_body(stream, body)
        if body.is_a?(::Rack::BodyProxy)
          begin
            body.each { |part|
              stream.send_data(part, end_stream: false)
            }
          ensure
            body.close
          end
          stream.send_data(nil, end_stream: true)
        else
          stream.send_data(body, end_stream: true)
        end
      end

      def extract_push(r_rawheaders)
        _, pushs = r_rawheaders.find { |k, v| k == "plum.serverpush" }
        if pushs
          pushs.split(";").map { |push| push.split(" ", 2) }
        else
          []
        end
      end

      def handle_request(stream, headers, data)
        env = new_env(headers, data)
        r_status, r_rawheaders, r_body = @app.call(env)
        r_headers = extract_headers(r_status, r_rawheaders)
        r_topushs = extract_push(r_rawheaders)

        stream.send_headers(r_headers, end_stream: false)
        r_pushstreams = r_topushs.map { |method, path|
          preq = { ":authority" => headers.find { |k, v| k == ":authority" }[1],
                   ":method" => method.to_s.upcase,
                   ":scheme" => headers.find { |k, v| k == ":scheme" }[1],
                   ":path" => path }
          st = stream.promise(preq)
          [st, preq]
        }

        send_body(stream, r_body)

        r_pushstreams.each { |st, preq|
          penv = new_env(preq, "")
          p_status, p_h, p_body = @app.call(penv)
          p_headers = extract_headers(p_status, p_h)
          st.send_headers(p_headers, end_stream: false)
          send_body(st, p_body)
        }
      end

      def new_env(h, data)
        headers = h.group_by { |k, v| k }.map { |k, kvs|
          if k == "cookie"
            [k, kvs.map(&:last).join("; ")]
          else
            [k, kvs.first.last]
          end
        }.to_h

        cmethod = headers[":method"]
        cpath = headers[":path"]
        cpath_name, cpath_query = cpath.split("?", 2).map(&:to_s)
        cauthority = headers[":authority"]
        cscheme = headers[":scheme"]
        ebase = {
          "REQUEST_METHOD"    => cmethod,
          "SCRIPT_NAME"       => "",
          "PATH_INFO"         => cpath_name,
          "QUERY_STRING"      => cpath_query.to_s,
          "SERVER_NAME"       => cauthority.split(":").first,
          "SERVER_PORT"       => (cauthority.split(":").last || 443), # TODO: forwarded header (RFC 7239)
        }

        headers.each {|key, value|
          unless key.start_with?(":") && key.include?(".")
            ebase["HTTP_" + key.gsub("-", "_").upcase] = value
          end
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

      def extract_headers(r_status, r_h)
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

        rbase
      end
    end
  end
end
