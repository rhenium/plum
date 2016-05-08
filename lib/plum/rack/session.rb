# frozen-string-literal: true

using Plum::BinaryString

module Plum
  module Rack
    INVALID_HEADERS = Set["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade"].freeze

    class Session
      attr_reader :app, :plum

      def initialize(svc, sock, plum)
        @svc = svc
        @app = svc.app
        @sock = sock
        @plum = plum
        @logger = svc.logger
        @config = svc.config
        @remote_addr = sock.peeraddr.last
        @threadpool = svc.threadpool

        setup_plum
      rescue Errno::ENOTCONN
        # TCP connection reset while doing TLS handshake
      end

      def stop
        @plum.close
      end

      def to_io
        @sock.to_io
      end

      def run
        while !@sock.closed? && !@sock.eof?
          @plum << @sock.readpartial(1024)
        end
      ensure
        stop
      end

      private
      def setup_plum
        @plum.on(:connection_error) { |ex| @logger.error(ex) }

        # @plum.on(:stream) { |stream| @logger.debug("new stream: #{stream}") }
        @plum.on(:stream_error) { |stream, ex|
          if [:cancel, :refused_stream].include?(ex.http2_error_type)
            @logger.debug("stream was cancelled: #{stream}")
          else
            @logger.error(ex)
          end
        }

        reqs = {}
        @plum.on(:headers) { |stream, h|
          reqs[stream] = { headers: h, data: "".b }
        }

        @plum.on(:data) { |stream, d|
          reqs[stream][:data] << d # TODO: store to file?
          check_window(stream)
        }

        @plum.on(:end_stream) { |stream|
          req = reqs.delete(stream)
          err = proc { |err|
            stream.send_headers({ ":status" => 500 }, end_stream: true)
            @logger.error(err)
          }
          if @threadpool
            @threadpool.acquire(err) {
              handle_request(stream, req[:headers], req[:data])
            }
          else
            begin
              handle_request(stream, req[:headers], req[:data])
            rescue
              err.call($!)
            end
          end
        }
      end

      def check_window(stream)
        ws = @plum.local_settings[:initial_window_size]
        stream.window_update(ws) if stream.recv_remaining_window < (ws / 2)
        @plum.window_update(ws) if @plum.recv_remaining_window < (ws / 2)
      end

      def send_body(stream, body)
        begin
          if body.respond_to?(:to_str)
            stream.send_data(body, end_stream: true)
          elsif body.respond_to?(:readpartial) && body.respond_to?(:eof?)
            until body.eof?
              stream.send_data(body.readpartial(65536), end_stream: body.eof?)
            end
          else
            body.each { |part| stream.send_data(part, end_stream: false) }
            stream.send_data(end_stream: true)
          end
        ensure
          body.close if body.respond_to?(:close)
        end
      end

      def extract_push(reqheaders, extheaders)
        pushs = extheaders["plum.serverpush"]
        return nil unless pushs

        authority = reqheaders.find { |k, v| k == ":authority" }[1]
        scheme = reqheaders.find { |k, v| k == ":scheme" }[1]

        pushs.split(";").map { |push|
          method, path = push.split(" ", 2)
          {
            ":authority" => authority,
            ":method" => method.upcase,
            ":scheme" => scheme,
            ":path" => path
          }
        }
      end

      def handle_request(stream, headers, data)
        env = new_env(headers, data)
        r_status, r_rawheaders, r_body = @app.call(env)
        r_headers, r_extheaders = extract_headers(r_status, r_rawheaders)
        if @config[:server_push] && @plum.push_enabled?
          push_preqs = extract_push(headers, r_extheaders)
        end

        no_body = r_body.respond_to?(:empty?) && r_body.empty?

        stream.send_headers(r_headers, end_stream: no_body)

        if push_preqs
          push_preqs.map! { |preq|
            [stream.promise(preq), preq]
          }
        end

        send_body(stream, r_body) unless no_body

        if push_preqs
          push_preqs.each { |st, preq|
            penv = new_env(preq, "".b)
            p_status, p_h, p_body = @app.call(penv)
            p_headers, _ = extract_headers(p_status, p_h)
            pno_body = p_body.respond_to?(:empty?) && p_body.empty?
            st.send_headers(p_headers, end_stream: pno_body)
            send_body(st, p_body) unless pno_body
          }
        end
      end

      def new_env(h, data)
        ebase = {
          "rack.version"      => ::Rack::VERSION,
          "rack.input"        => StringIO.new(data),
          "rack.errors"       => $stderr,
          "rack.multithread"  => true,
          "rack.multiprocess" => false,
          "rack.run_once"     => false,
          "rack.hijack?"      => false,
          "SCRIPT_NAME"       => "",
          "REMOTE_ADDR"       => @remote_addr,
          "HTTP_VERSION"      => "HTTP/2.0", # Rack::CommonLogger uses
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
            ebase["SERVER_PORT"] = cport || "443"
          when ":scheme"
            ebase["rack.url_scheme"] = v
          else
            unless k.start_with?(":") # ignore unknown pseudo-headers
              if k == "cookie" && ebase["HTTP_COOKIE"]
                if ebase["HTTP_COOKIE"].frozen?
                  (ebase["HTTP_COOKIE"] += "; ") << v
                else
                  ebase["HTTP_COOKIE"] << "; " << v
                end
              else
                ebase["HTTP_" + k.tr("-", "_").upcase!] = v
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
        rext = {}

        r_h.each do |key, v_|
          if key.include?(".")
            rext[key] = v_
          else
            key = key.downcase

            if "set-cookie" == key
              rbase[key] = v_.gsub("\n", "; ") # RFC 7540 8.1.2.5
            elsif !INVALID_HEADERS.member?(key)
              rbase[key] = v_.tr("\n", ",") # RFC 7230 7
            end
          end
        end

        [rbase, rext]
      end
    end
  end
end
