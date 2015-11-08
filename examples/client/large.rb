# -*- frozen-string-literal: true -*-
# client/large.rb: download 3 large files in parallel
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "plum"

def log(s)
  puts "[#{Time.now.strftime("%Y/%m/%d %H:%M:%S.%L")}] #{s}"
end

Plum::Client.start("http2.golang.org", 443, http2_settings: { max_frame_size: 32768 }) { |rest|
  3.times { |i|
    rest.get_async("/file/go.src.tar.gz",
                   "accept-encoding" => "identity;q=1") { |res|
      log "#{i}: #{res.status}"
      res.on_chunk { |chunk|
        log "#{i}: chunk: #{chunk.size}"
      }
    }
  }
}
