# Plum: An HTTP/2 Library for Ruby
A pure Ruby HTTP/2 server and client implementation.

WARNING: Plum is currently under heavy development. You *will* encounter bugs when using it.

[![Circle CI](https://circleci.com/gh/rhenium/plum.svg?style=svg)](https://circleci.com/gh/rhenium/plum) [![Build Status](https://travis-ci.org/rhenium/plum.png?branch=master)](https://travis-ci.org/rhenium/plum) [![Code Climate](https://codeclimate.com/github/rhenium/plum/badges/gpa.svg)](https://codeclimate.com/github/rhenium/plum) [![Test Coverage](https://codeclimate.com/github/rhenium/plum/badges/coverage.svg)](https://codeclimate.com/github/rhenium/plum/coverage)

## Requirements
* Ruby 2.3
* OpenSSL 1.0.2 or newer (HTTP/2 requires ALPN)
* Optional:
  * [http_parser.rb gem](https://rubygems.org/gems/http_parser.rb) (HTTP/1.x parser; if you use "http" URI scheme)
  * [rack gem](https://rubygems.org/gems/rack) (if you use Plum as Rack server)

## Installation
```sh
gem install plum
```

## Usage
* Documentation: http://www.rubydoc.info/gems/plum
* Some examples are in `examples/`

### As a Rack-compatible server

Most existing Rack-based applications should work without modification.

```ruby
# config.ru
App = -> env {
  [
    200,
    { "Content-Type" => "text/plain" },
    ["request: #{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"]
  ]
}

run App
```

You can run it:

```sh
% plum -e production -p 8080 --https --cert server.crt --key server.key config.ru
```

NOTE: If `--cert` and `--key` are omitted, a temporary dummy certificate will be generated.

### As a HTTP/2 (HTTP/1.x) client library
If the server does't support HTTP/2, `Plum::Client` tries to use HTTP/1.x instead.

```
   +-----------------+
   |:http2 option    | false
   |(default: true)  |-------> HTTP/1.x
   +-----------------+
            v true
   +-----------------+
   |:scheme option   | "http"
   |(default:"https")|-------> Try Upgrade from HTTP/1.1
   +-----------------+
            v "https"
   +-----------------+
   | ALPN            | failed
   | negotiation     |-------> HTTP/1.x
   +-----------------+
            | "h2"
            v
          HTTP/2
```

##### Sequential request
```ruby
client = Plum::Client.start("http2.rhe.jp", user_agent: "nyaan")
res1 = client.get("/", headers: { "accept" => "*/*" }).join
puts res1.body # => "..."
res2 = client.post("/post", "data").join
puts res2.body # => "..."

client.close
```

##### Parallel request
```ruby
res1 = res2 = nil
Plum::Client.start("rhe.jp", 443, http2_settings: { max_frame_size: 32768 }) { |client|
  res1 = client.get("/")
  res2 = client.post("/post", "data")
  # res1.status == nil ; because it's async request
} # wait for response(s) and close

p res1.status # => "200"
```

##### Download a large file
```ruby
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
```

## TODO
* **Better API**
* Plum::Client
  * PING frame handling
  * Server Push support
  * Stream Priority support
  * Better HTTP/1.x support

## License
MIT License
