require "coveralls"
Coveralls.wear!

require "plum"
require "timeout"
require "minitest"
require "minitest/unit"
require "minitest/autorun"
require "minitest/pride"
require "utils"

LISTEN_PORT = ENV["PLUM_LISTEN_PORT"] || 40444
