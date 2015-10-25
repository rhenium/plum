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
            data = "".force_encoding(Encoding::BINARY)
          }

          stream.on(:headers) { |h|
            headers = h
          }

          stream.on(:data) { |d|
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
        ebase = {
          "SCRIPT_NAME"       => "",
          "rack.version"      => ::Rack::VERSION,
          "rack.input"        => StringIO.new(data),
          "rack.errors"       => $stderr,
          "rack.multithread"  => true,
          "rack.multiprocess" => false,
          "rack.run_once"     => false,
          "rack.hijack?"      => false,
        }

        h.each { |k, v|
          case k
          when ":method"
            ebase["REQUEST_METHOD"] = v
          when ":path"
            cpath_name, cpath_query = v.split("?", 2)
            ebase["PATH_INFO"] = cpath_name
            ebase["QUERY_STRING"] = cpath_query || ""
          when ":authority"
            chost, cport = v.split(":", 2)
            ebase["SERVER_NAME"] = chost
            ebase["SERVER_PORT"] = (cport || 443).to_i
          when ":scheme"
            ebase["rack.url_scheme"] = v
          else
            if k.start_with?(":")
              # unknown HTTP/2 pseudo-headers
            else
              if "cookie" == k && headers["HTTP_COOKIE"]
                ebase["HTTP_COOKIE"] << "; " << v
              else
                ebase["HTTP_" << k.tr("-", "_").upcase!] = v
              end
            end
          end
        }

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

          key = key.downcase
          if "set-cookie".freeze == key
            rbase[key] = v_.gsub("\n", "; ") # RFC 7540 8.1.2.5
          else
            key = key.byteshift(2) if key.start_with?("x-")
            rbase[key] = v_.tr("\n", ",") # RFC 7230 7
          end
        end

        rbase
      end
    end
  end
end
