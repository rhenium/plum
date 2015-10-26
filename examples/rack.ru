$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum/rack"

class App2
  def call(env)
    if env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/"
      [
        200,
        { "Content-Type" => "text/html" },
        ["8 bytes-" * 512]
      ]
    else
      [
        404,
        { "Content-Type" => "text/html" },
        ["#{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"]
      ]
    end
  end
end

run App2.new
