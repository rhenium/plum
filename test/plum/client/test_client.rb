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
    server_thread = start_tls_server
    res2 = nil
    Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) { |client|
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
    server_thread = start_tls_server
    assert_raises(OpenSSL::SSL::SSLError) {
      Client.start("127.0.0.1", LISTEN_PORT, https: true, verify_mode: OpenSSL::SSL::VERIFY_PEER)
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
      begin
        Timeout.timeout(3) {
          sock = ssl_server.accept
          plum = HTTPSServerConnection.new(sock)

          plum.on(:stream) { |stream|
            headers = data = nil
            stream.on(:headers) { |h|
              headers = h }
            stream.on(:data) { |d|
              data = d }
            stream.on(:end_stream) {
              stream.respond({ ":status" => 200 }, headers.to_h[":method"] + headers.to_h["header"] + data.to_s) }
          }

          yield plum if block_given?
          plum.run
        }
      rescue OpenSSL::SSL::SSLError
      rescue Timeout::Error
        flunk "server timeout"
      rescue => e
        flunk e
      ensure
        tcp_server.close
      end
    }
  end
end
