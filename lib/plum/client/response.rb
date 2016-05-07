# -*- frozen-string-literal: true -*-
module Plum
  class Response
    # The response headers
    # @return [Hash<String, String>]
    attr_reader :headers

    # @api private
    def initialize(auto_decode: true, **options)
      @body = Queue.new
      @finished = false
      @failed = false
      @body = []
      @auto_decode = auto_decode
      @on_chunk = @on_finish = nil
    end

    # Returns the HTTP status code.
    # @return [String] the HTTP status code
    def status
      @headers && @headers[":status"]
    end

    # Returns the header value that correspond to the header name.
    # @param key [String] the header name
    # @return [String] the header value
    def [](key)
      @headers[key.to_s.downcase]
    end

    # Returns whether the response is complete or not.
    # @return [Boolean]
    def finished?
      @finished
    end

    # Returns whether the request has failed or not.
    # @return [Boolean]
    def failed?
      @failed
    end

    # Set callback tha called when received a chunk of response body.
    # @yield [chunk] A chunk of the response body.
    def on_chunk(&block)
      raise "Body already read" if @on_chunk
      raise ArgumentError, "block must be given" unless block_given?
      @on_chunk = block
      unless @body.empty?
        @body.each(&block)
        @body.clear
      end
    end

    # Set callback that will be called when the response finished.
    def on_finish(&block)
      raise ArgumentError, "block must be given" unless block_given?
      if finished?
        yield
      else
        @on_finish = block
      end
    end

    # Returns the complete response body. Use #each_body instead if the body can be very large.
    # @return [String] the whole response body
    def body
      raise "Body already read" if @on_chunk
      raise "Response body is not complete" unless finished?
      @body.join
    end

    private
    # internal: set headers and setup decoder
    def set_headers(headers)
      @headers = headers.freeze
      @decoder = setup_decoder
    end

    def add_chunk(encoded)
      chunk = @decoder.decode(encoded)
      if @on_chunk
        @on_chunk.call(chunk)
      else
        @body << chunk
      end
    end

    def finish
      @finished = true
      @decoder.finish
      @on_finish.call if @on_finish
    end

    def fail(ex = nil)
      @failed = ex || true # FIXME
    end

    def setup_decoder
      if @auto_decode
        klass = Decoders::DECODERS[@headers["content-encoding"]]
      end
      klass ||= Decoders::Base
      klass.new
    end
  end
end
