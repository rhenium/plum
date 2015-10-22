$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum/rack"
require "sinatra"

set :server, :plum
enable :logging, :dump_errors, :raise_errors

get "/" do
  "get: #{params}"
end

post "/" do
  "post: " + params.to_s
end
