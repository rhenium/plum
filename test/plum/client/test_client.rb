require "test_helper"

using Plum::BinaryString
class ClientTest < Minitest::Test
  def test_request
    server_thread = start_tls_server
    client = Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
    res1 = client.request({ ":path" => "/", ":method" => "POST", ":scheme" => "https", "header" => "ccc" }, "abc")
    assert_equal("POSTcccabc", res1.body)
    res2 = client.put("/", "aaa", { ":scheme" => "https", "header" => "ccc" })
    assert_equal("PUTcccaaa", res2.body)
    client.close
  ensure
    server_thread.join
  end

  def test_request_async
    res2 = nil
    client = nil
    server_thread = start_tls_server
    Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) { |c|
      client = c
      res1 = client.request_async({ ":path" => "/", ":method" => "GET", ":scheme" => "https", "header" => "ccc" }) { |res1|
        assert(res1.headers)
      }
      assert_nil(res1.headers)

      res2 = client.get_async("/", "header" => "ccc")
    }
    assert(res2.headers)
    assert_equal("GETccc", res2.body)
  ensure
    server_thread.join
  end

  def test_verify
    client = nil
    server_thread = start_tls_server
    assert_raises(OpenSSL::SSL::SSLError) {
      client = Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_PEER)
    }
  ensure
    server_thread.join
  end

  def test_raise_error_sync
    client = nil
    server_thread = start_tls_server
    Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) { |c|
      client = c
      assert_raises(LocalConnectionError) {
        client.get("/connection_error")
      }
    }
  ensure
    server_thread.join
  end

  def test_raise_error_async_seq_wait
    server_thread = start_tls_server
    client = Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
    res = client.get_async("/error_in_data")
    assert_raises(LocalConnectionError) {
      client.wait(res)
    }
    client.close
  ensure
    server_thread.join
  end

  def test_raise_error_async_seq_wait_headers
    server_thread = start_tls_server
    client = Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
    res = client.get_async("/error_in_data")
    client.wait_headers(res)
    data = String.new
    tt = Thread.new { client.wait }
    assert_raises(LocalConnectionError) {
      res.each_chunk { |c| data << c }
    }
    tt.join
    client.close
    assert_equal("a", data)
  ensure
    server_thread.join
  end

  def test_raise_error_async_block
    client = nil
    server_thread = start_tls_server
    assert_raises(LocalConnectionError) {
      Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) { |c|
        client = c
        client.get_async("/connection_error") { |res| flunk "success??" }
      } # wait
    }
  ensure
    server_thread.join
  end

  private
  def start_tls_server(&block)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.alpn_select_cb = -> protocols { "h2" }
    ctx.cert = TLS_CERT
    ctx.key = TLS_KEY
    tcp_server = TCPServer.new("127.0.0.1", LISTEN_PORT)
    ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)

    server_thread = Thread.new {
      plum = nil
      begin
        Timeout.timeout(3) {
          sock = ssl_server.accept
          plum = HTTPSServerConnection.new(sock)

          plum.on(:stream) { |stream|
            headers = data = nil
            stream.on(:headers) { |h|
              headers = h.to_h }
            stream.on(:data) { |d|
              data = d }
            stream.on(:end_stream) {
              case headers[":path"]
              when "/connection_error"
                plum.goaway(:protocol_error)
              when "/error_in_data"
                stream.send_headers({ ":status" => 200 }, end_stream: false)
                stream.send_data("a", end_stream: false)
                raise ExampleError, "example error"
              else
                stream.respond({ ":status" => 200 }, headers.to_h[":method"] + headers.to_h["header"].to_s + data.to_s)
              end } }

          yield plum if block_given?

          while !sock.closed? && !sock.eof?
            plum << sock.readpartial(1024)
          end
        }
      rescue OpenSSL::SSL::SSLError
      rescue Timeout::Error
        flunk "server timeout"
      rescue ExampleError => e
        plum.goaway(:internal_error) if plum
      ensure
        tcp_server.close
      end
    }
  end
end
