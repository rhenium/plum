# Plum [![Build Status](https://travis-ci.org/rhenium/plum.png?branch=master)](https://travis-ci.org/rhenium/plum) [![Code Climate](https://codeclimate.com/github/rhenium/plum/badges/gpa.svg)](https://codeclimate.com/github/rhenium/plum) [![Test Coverage](https://codeclimate.com/github/rhenium/plum/badges/coverage.svg)](https://codeclimate.com/github/rhenium/plum/coverage)
A minimal implementation of HTTP/2 server. (WIP)

## Requirements
* OpenSSL 1.0.2+
* Ruby 2.2 with [ALPN support patch](https://gist.github.com/rhenium/b1711edcc903e8887a51).

## TODO
* "http" URIs support (upgrade from HTTP/1.1)
* Stream Priority (RFC 7540 5.3)
* Better HPACK encoding (RFC 7541)
* SNI support
* TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 support (need patching openssl)
* Better API
* Better Code Climate
* More test code

## License
MIT License
