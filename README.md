# Plum: An HTTP/2 Library for Ruby

A pure Ruby HTTP/2 server and client implementation.

WARNING: Plum is currently under heavy development. You *will* encounter bugs when using it.

## Requirements

* Ruby/OpenSSL 2.0
* OpenSSL 1.0.2 or newer
* [http_parser.rb gem](https://rubygems.org/gems/http_parser.rb) - if you need HTTP/2 without TLS or HTTP/1.1 support
* [rack gem](https://rubygems.org/gems/rack) - if you use plum as a Rack server


## Installation

You can install via rubygems:

~~~sh
gem install plum
~~~

then require it:

~~~ruby
require "plum"
~~~

## Usage

* Documentation: http://www.rubydoc.info/gems/plum
* Some examples are in `examples/`


### As a Rack-compatible server

Most existing Rack-based applications should work without modification.

~~~ruby
# config.ru
App = -> env {
  [
    200,
    { "Content-Type" => "text/plain" },
    ["request: #{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"]
  ]
}

run App
~~~

You can run it:

~~~sh
% plum -e production -p 8080 --https --cert server.crt --key server.key config.ru
~~~

NOTE: If `--cert` and `--key` are omitted, a temporary dummy certificate will be generated.

My website [https://rhe.jp](https://rhe.jp) is using plum as a Rack server.


### As a HTTP/2 (HTTP/1.x) client library

If the server doesn't support HTTP/2, it falls back to HTTP/1.1 seamlessly.

~~~
   +-----------------+
   |:https option    | false
   |(default: true)  |-------> Try Upgrade from HTTP/1.1
   +-----------------+
            | true
            v
   +-----------------+
   | ALPN            | failed
   | negotiation     |-------> HTTP/1.x
   +-----------------+
            | "h2"
            v
          HTTP/2
~~~


##### Sequential request

~~~ruby
client = Plum::Client.start("http2.rhe.jp", user_agent: "nyaan")
res1 = client.get("/", headers: { "accept" => "*/*" }).join
puts res1.body # => "..."
res2 = client.post("/post", "data").join
puts res2.body # => "..."

client.get("/clockstream").on_headers { |res|
  puts "status: #{res.status}, headers: #{res.headers}"
}.on_chunk { |chunk|
  puts chunk
}.on_finish {
  puts "finish!"
}.join

client.close
~~~


##### Parallel request

~~~ruby
res1 = res2 = nil
Plum::Client.start("rhe.jp", 443, http2_settings: { max_frame_size: 32768 }) { |client|
  res1 = client.get("/")
  res2 = client.post("/post", "data")
  # res1.status == nil ; because it's async request
} # wait for response(s) and close

p res1.status # => "200"
~~~


##### Download a large file

~~~ruby
# the value of hostname option will be used in SNI and :authority header
Plum::Client.start("http2.rhe.jp", 443, hostname: "assets.rhe.jp") { |client|
  client.get("/large") do |res| # called when received response headers
    p res.status # => "200"
    File.open("/tmp/large.file", "wb") { |file|
      res.on_chunk do |chunk| # called when each chunk of response body arrived
        file << chunk
      end
    }
  end
}
~~~


## TODO

* Better API design
* Better server push support
* Stream priority support

Of course ideas and pull requests are welcome.

## Hacking

Clone this Git repository and run `bundle install` to install development dependencies. You can run test with `rake test`. The tests are written with Minitest.


## License
MIT License
