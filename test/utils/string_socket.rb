class StringSocket
  extend Forwardable
  def_delegators :@rio, :readpartial
  def_delegators :@wio, :<<, :write

  attr_reader :rio, :wio

  def initialize(str)
    @rio = StringIO.new(str)
    @wio = StringIO.new
  end
end
