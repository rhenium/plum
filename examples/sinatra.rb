$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "rack/handler/plum"
require "sinatra"

set :server, :plum
enable :logging, :dump_errors, :raise_errors

get "/" do
  p request
  "get: #{params}"
end

post "/" do
  "post: " + params.to_s
end
