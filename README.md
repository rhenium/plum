# Plum [![Build Status](https://travis-ci.org/rhenium/plum.png?branch=master)](https://travis-ci.org/rhenium/plum) [![Code Climate](https://codeclimate.com/github/rhenium/plum/badges/gpa.svg)](https://codeclimate.com/github/rhenium/plum) [![Test Coverage](https://codeclimate.com/github/rhenium/plum/badges/coverage.svg)](https://codeclimate.com/github/rhenium/plum/coverage)
A pure Ruby HTTP/2 implementation.

## Requirements
* Ruby
  * Ruby 2.2 with [ALPN support patch](https://gist.github.com/rhenium/b1711edcc903e8887a51) and [ECDH support patch (r51348)](https://bugs.ruby-lang.org/projects/ruby-trunk/repository/revisions/51348/diff?format=diff)
  * or latest Ruby 2.3.0-dev
* OpenSSL 1.0.2 or newer (HTTP/2 requires ALPN)
* Optional:
  * [http_parser.rb gem](https://rubygems.org/gems/http_parser.rb) (HTTP/1.1 parser; if you use "http" URI scheme)
  * [rack gem](https://rubygems.org/gems/rack) if you use Plum as Rack server.

## Usage
### As a HTTP/2 client library
##### Sequential request
```ruby
client = Plum::Client.start("http2.rhe.jp", 443)
res1 = client.get("/")
puts res1.body # => "..."
res2 = client.post("/post", "data")
puts res2.body # => "..."

client.close
```

##### Parallel request
```ruby
client = Plum::Client.start("http2.rhe.jp", 443)
res1 = client.get_async("/")
res2 = client.post_async("/post", "data")
client.wait # wait for response(s)
client.close
p res1.status # => 200
```
or
```ruby
res1 = res2 = nil
Plum::Client.start("http2.rhe.jp", 443) { |client|
  res1 = client.get_async("/")
  res2 = client.post_async("/post", "data")
} # wait for response(s) and close

p res1.status # => 200
```

##### Download large file
```ruby
Plum::Client.start("http2.rhe.jp", 443) { |client|
  client.get_async("/large") do |res|
    p res.status # => 200
    File.open("/tmp/large.file", "wb") { |file|
      res.each_chunk do |chunk|
        file << chunk
      end
    }
  end
}
```

### As a Rack-compatible server

Most existing Rack-based applications (plum doesn't support Rack hijack API) should work without modification.

```ruby
# config.ru
App = -> env {
  [
    200,
    { "Content-Type" => "text/plain" },
    [" request: #{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"]
  ]
}

run App
```

You can run it:

```sh
% plum -e production -p 8080 --https config.ru
```

By default, Plum generates a dummy server certificate if `--cert` and `--key` options are not specified.

### As a library
* See documentation: http://www.rubydoc.info/gems/plum
* See examples in `examples/`
* [rhenium/plum-server](https://github.com/rhenium/plum-server) - A static-file server for https://rhe.jp and http://rhe.jp.

## TODO
* **Better API**

## License
MIT License
