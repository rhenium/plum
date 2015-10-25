# Plum [![Build Status](https://travis-ci.org/rhenium/plum.png?branch=master)](https://travis-ci.org/rhenium/plum) [![Code Climate](https://codeclimate.com/github/rhenium/plum/badges/gpa.svg)](https://codeclimate.com/github/rhenium/plum) [![Test Coverage](https://codeclimate.com/github/rhenium/plum/badges/coverage.svg)](https://codeclimate.com/github/rhenium/plum/coverage)
A minimal pure Ruby implementation of HTTP/2 library / server.

## Requirements
* Ruby
  * Ruby 2.2 with [ALPN support patch](https://gist.github.com/rhenium/b1711edcc903e8887a51) and [ECDH support patch (r51348)](https://bugs.ruby-lang.org/projects/ruby-trunk/repository/revisions/51348/diff?format=diff)
  * or latest Ruby 2.3.0-dev
* OpenSSL 1.0.2 or newer (HTTP/2 requires ALPN)
* Optional:
  * [http-parser.rb gem](https://rubygems.org/gems/http_parser.rb) (HTTP/1.1 parser; if you use "http" URI scheme)
  * [rack gem](https://rubygems.org/gems/rack) if you use Plum as Rack server.

## Usage
### As a library
See examples in `examples/`

### As a Rack-compatible server
Insert `require "plum/rack"` to your `config.ru`
```ruby
require "plum/rack"

App = -> env {
  [
    200,
    { "Content-Type" => "text/plain" },
    [" request: #{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"]
  ]
}

run App
```
Then run it with:
```sh
% plum -e production -p 8080 --https config.ru
```
By default, Plum generates a dummy server certificate if `--cert` and `--key` options are not specified.

## Examples
* examples/ - Minimal usage.
* [rhenium/plum-server](https://github.com/rhenium/plum-server) - A example server for https://rhe.jp and http://rhe.jp.

## TODO
* **Better API**

## License
MIT License
