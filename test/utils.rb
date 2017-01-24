require "test/unit"
require "timeout"
require "socket"
require "forwardable"
gem "openssl"
require "openssl"

require "plum"
require_relative "utils/assertions"
require_relative "utils/string_socket"

include Plum
LISTEN_PORT = ENV["PLUM_LISTEN_PORT"] || 44444
ExampleError = Class.new(RuntimeError)

class Test::Unit::TestCase
  def open_client_connection(scheme = :https)
    io = StringIO.new
    @_ccon = ClientConnection.new(io.method(:write))
    @_ccon << Frame::Settings.ack.assemble
    @_ccon << Frame::Settings.new.assemble
    if block_given?
      yield @_ccon
    else
      @_ccon
    end
  end

  def open_server_connection(scheme = :https)
    @_io = StringIO.new
    @_con = (scheme == :https ? ServerConnection : HTTPServerConnection).new(@_io.method(:write))
    @_con << Connection::CLIENT_CONNECTION_PREFACE
    @_con << Frame::Settings.new.assemble
    if block_given?
      yield @_con
    else
      @_con
    end
  end

  def open_new_stream(arg1 = nil, state: :idle, **kwargs)
    if arg1.is_a?(ServerConnection)
      con = arg1
    else
      con = open_server_connection
    end

    @_stream = con.instance_eval { stream(@max_stream_ids[1] + 2) }
    @_stream.set_state(state)
    @_stream.update_dependency(**kwargs)
    if block_given?
      yield @_stream
    else
      @_stream
    end
  end

  def sent_frames(io = nil)
    resp = (io || @_io).string.dup.force_encoding(Encoding::BINARY)
    frames = []
    while f = Frame.parse!(resp)
      frames << f
    end
    frames
  end

  def parse_frames(io, &blk)
    pos = io.string.bytesize
    blk.call
    resp = io.string.byteslice(pos, io.string.bytesize - pos).force_encoding(Encoding::BINARY)
    frames = []
    while f = Frame.parse!(resp)
      frames << f
    end
    frames
  end

  def parse_frame(io, &blk)
    frames = capture_frames(io, &blk)
    assert_equal(1, frames.size, "Supplied block sent no frames or more than 1 frame")
    frames.first
  end

  def rsa2048
    OpenSSL::PKey.read <<~EOF
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAxM6IQBZ1z5JDkM5d38Lp8UKP1iR+TXKQVphqKcpiMOTN08LW
      hfuHQcIXu/kIniA85u4q1PRiFDviSIPQ1skY7T4qxxmaZhotsCaE2LUMOm/lzSZi
      bDMdHsjmpFt9tSU6eEe/BFdcjPNRVVhMYTERiCtUtoudW9r51ECz7IoZSSrBMbiW
      jtdVVL9/tRcufykmJFHMLfiQWgTDJtaCOZ7WWILUz6hR+3yuSu9m2AuxtlOJ+Qzy
      6qX3K1whhUzFG14jLd3hbsguHrRIYyhEFIgLlPU7C4zaOOwwlNyYie2ZEe61Eofr
      aCqvLJnM2p/s7+jbyDcz8TTSoMIqovQmM0z+bwIDAQABAoIBAHXtY8szKijU9dOB
      NNLt0oyUW+fvOhdiPIcHESY1dRzjHUp0h2MFUwjeKqaiFL3bh2LA971fKp4BPBhD
      lBH/sgYGqE9hUhk4OoRAsH3CDq+9eS+yfmtjPWHC9CEsCWlQA3crVpRdXMHA0s2W
      +T2Lz3uOq1Yu1n3B+s1qb+We4oPqIkYj3qHpP+BxQYrL9y4L8Hk+dJZviYanlrcG
      MV8CH8WnwqbwkQRDwxE04qALrOWeIE44zY/ZzNCOs8Q4MzyLRFSyAOURECoh4V//
      1eNZd0ojiyxRlpRuDkVt7zn6+FdxZrRySuJxEwFQ5Qanl37yMJb/NN8ill3D8T9L
      vjRTwXECgYEA974PL0IVZmhuk5FcyObFaNDSL196evgUAnPxMQwATwXMzKPw6azE
      rRnBopoS4zq4XWXWR/GAIskmF8vag9zf/za9f8QlJzqT3eQE4mGZeZfpic2WYtBZ
      AojLgEwMGcof4TGHv0dCdSjuw95dXvL7qUopqfiB95TLSv2VXkW6arMCgYEAy13Z
      K2RUt0DLafs/nmNywYDt/isMTTkL0tf4QjdB8Os4C1WcyMUSd1yYblrmsNN8/eWe
      gOHrFt/zwD/kz0z5f/LBsIoEI3ZmJWjL29FQhSllM8q3JfkwCOfH5TmNDF/aAA1t
      b0g+LSSxoUwttLu2euJk64uTGTWXrU+7BxVWq1UCgYAtaVRFOFrN28SxHgsg9FQp
      Q2XTsy+zTLf2PyRt9iI0Wf7RYBev7bBbfoYk9RMTPdc/n4QoydbQCYkHAaH7W8hf
      crxHqD+bMjyahspyaKuGQ1dWoC25zTETqtmKmeX58Dfpwnd8k2ZWLXuewarh1a5V
      uLdsZZYFOOwOwe7YSfXCywKBgQCU2HCd2MZEhhEb1b/fjowsYtBOKnXLg4hK3rWe
      yVDjI1YWvaeOLudwI36RrsiP/YrLTievzyrAyFNgj6NJst4eLrBjJPEYf40NrmEe
      11mmzQB8Ys+f5H2q1vIwrOm2d+VYCnvhai/P3L6B/v6o/Ib39AHHgJW+asJEIEoU
      SiLwLQKBgHEY7WLyqs7dPf9ZxJErZH2eTstMtj649750GsfQGqr0Ul/zWWSq6QPJ
      lzVB2B+g/m6xnPQjn7dXPLeZ3lLbmcLTpl5O9T65qDXgVIzKPX4Ybd4ozjDOfHW5
      u5vKC+xEwJK+17JJ78Mb8XH7vmujCmKLueEuZtgrT6P9Cke26yEN
      -----END RSA PRIVATE KEY-----
    EOF
  end

  def issue_cert(dn, pubkey)
    cert = OpenSSL::X509::Certificate.new
    ca_cert = cert
    ca_key = pubkey
    cert.version = 2
    cert.serial = 12345
    cert.subject = OpenSSL::X509::Name.parse_rfc2253(dn)
    cert.issuer = ca_cert.subject
    cert.public_key = pubkey
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.sign(ca_key, "sha256")
    cert
  end
end
