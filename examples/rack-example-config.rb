log "logs/plum.log"
debug false
server_push true
threaded false # create a new thread per request
fallback_legacy "127.0.0.1:8080" # forward if client doesn't support HTTP/2

user "nobody"
group "nobody"

# listeners may be multiple
listener :unix, { path: "/tmp/plum.sock", mode: 600 }
listener :tcp, { hostname: "0.0.0.0", port: 80 }
listener :tls, {
  hostname: "0.0.0.0",
  port: 443,
  certificate: "/path/to/cert", # chained certifcate is acceptable
  certificate_key: "/path/to/key",
  sni: {
    "rhe.jp" => { # SNI, key must be String. If none matches, default certificate (above) is used
      certificate: "/path/to/rhe.jp/cert",
      certificate_key: "/path/to/rhe.jp/key"
    },
  }
}
