# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module Rack
    INVALID_HEADERS = Set["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade"].freeze

    class Session
      attr_reader :app, :plum

      def initialize(app:, plum:, sock:, logger:, config:, remote_addr: "127.0.0.1")
        @app = app
        @plum = plum
        @sock = sock
        @logger = logger
        @config = config
        @remote_addr = remote_addr
        @request_thread = {} # used if threaded

        setup_plum
      end

      def stop
        @plum.close
      end

      def run
        while !@sock.closed? && !@sock.eof?
          @plum << @sock.readpartial(1024)
        end
      rescue Errno::EPIPE, Errno::ECONNRESET => e
      rescue StandardError => e
        @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
      ensure
        @request_thread.each { |stream, thread| thread.kill }
        stop
      end

      private
      def setup_plum
        @plum.on(:connection_error) { |ex| @logger.error(ex) }

        # @plum.on(:stream) { |stream| @logger.debug("new stream: #{stream}") }
        @plum.on(:stream_error) { |stream, ex| @logger.error(ex) }

        reqs = {}
        @plum.on(:headers) { |stream, h|
          reqs[stream] = { headers: h, data: String.new.force_encoding(Encoding::BINARY) }
        }

        @plum.on(:data) { |stream, d|
          reqs[stream][:data] << d # TODO: store to file?
        }

        @plum.on(:end_stream) { |stream|
          if @config[:threaded]
            @request_thread[stream] = Thread.new {
              handle_request(stream, reqs[stream][:headers], reqs[stream][:data])
            }
          else
            handle_request(stream, reqs[stream][:headers], reqs[stream][:data])
          end
        }
      end

      def send_body(stream, body)
        begin
          if body.is_a?(IO)
            stream.send_data(body, end_stream: true)
          elsif body.respond_to?(:size)
            last = body.size - 1
            i = 0
            body.each { |part|
              stream.send_data(part, end_stream: last == i)
              i += 1
            }
            stream.send_data(nil, end_stream: true) if i == 0
          else
            body.each { |part| stream.send_data(part, end_stream: false) }
            stream.send_data(nil, end_stream: true)
          end
        ensure
          body.close if body.respond_to?(:close)
        end
      end

      def extract_push(reqheaders, extheaders)
        if @config[:server_push] && @plum.push_enabled? && pushs = extheaders["plum.serverpush"]
          authority = reqheaders.find { |k, v| k == ":authority" }[1]
          scheme = reqheaders.find { |k, v| k == ":scheme" }[1]

          pushs.split(";").map { |push|
            method, path = push.split(" ", 2)
            {
              ":authority" => authority,
              ":method" => method.to_s.upcase,
              ":scheme" => scheme,
              ":path" => path
            }
          }
        else
          []
        end
      end

      def handle_request(stream, headers, data)
        env = new_env(headers, data)
        r_status, r_rawheaders, r_body = @app.call(env)
        r_headers, r_extheaders = extract_headers(r_status, r_rawheaders)

        stream.send_headers(r_headers, end_stream: false)

        push_sts = extract_push(headers, r_extheaders).map { |preq|
          [stream.promise(preq), preq]
        }

        send_body(stream, r_body)

        push_sts.each { |st, preq|
          penv = new_env(preq, "")
          p_status, p_h, p_body = @app.call(penv)
          p_headers = extract_headers(p_status, p_h)
          st.send_headers(p_headers, end_stream: false)
          send_body(st, p_body)
        }

        @request_thread.delete(stream)
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
              key.byteshift(2) if key.start_with?("x-")
              rbase[key] = v_.tr("\n", ",") # RFC 7230 7
            end
          end
        end

        [rbase, rext]
      end
    end
  end
end
