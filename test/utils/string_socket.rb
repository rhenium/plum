class StringSocket < IO
  # remove all methods
  (IO.instance_methods - Object.instance_methods).each { |symbol| undef_method symbol }

  extend Forwardable
  def_delegators :@rio, :readpartial
  def_delegators :@wio, :<<, :write

  attr_reader :rio, :wio

  def initialize(str = nil)
    @rio = StringIO.new(str.to_s)
    @wio = StringIO.new
  end
end
