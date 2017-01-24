# client/synchronous.rb: download 3 files in sequence
$LOAD_PATH.unshift File.expand_path("../../../lib", __FILE__)
require "plum"
require "zlib"

client = Plum::Client.start("http2.golang.org", 443)

reqinfo = client.get("/reqinfo").join
puts "/reqinfo: #{reqinfo.status}"

test = "test"
crc32 = client.put("/crc32", test).join
puts "/crc32{#{test}}: #{crc32.body}"
puts "Zlib.crc32: #{Zlib.crc32(test).to_s(16)}"

client.get("/clockstream")
  .on_headers { |res|
  puts "status: #{res.status}, headers: #{res.headers}"
  }.on_chunk { |chunk|
    puts chunk
  }.on_finish {
    puts "finish!"
  }.join
