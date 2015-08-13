# Plum [![Build Status](https://travis-ci.org/rhenium/plum.png?branch=master)](https://travis-ci.org/rhenium/plum) [![Code Climate](https://codeclimate.com/github/rhenium/plum/badges/gpa.svg)](https://codeclimate.com/github/rhenium/plum) [![Test Coverage](https://codeclimate.com/github/rhenium/plum/badges/coverage.svg)](https://codeclimate.com/github/rhenium/plum/coverage)
A minimal implementation of HTTP/2 server.

## Requirements
* OpenSSL 1.0.2+
* Ruby 2.2 with [ALPN support](https://gist.github.com/rhenium/b1711edcc903e8887a51) and [ECDH support (r51348)](https://bugs.ruby-lang.org/projects/ruby-trunk/repository/revisions/51348/diff?format=diff) or latest Ruby 2.3.0-dev.

## TODO
* "http" URIs support (upgrade from HTTP/1.1)
* Stream Priority (RFC 7540 5.3)
* Better API

## License
MIT License
