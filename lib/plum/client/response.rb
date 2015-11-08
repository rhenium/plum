# -*- frozen-string-literal: true -*-
module Plum
  class Response
    # The response headers
    # @return [Hash<String, String>]
    attr_reader :headers

    # @api private
    def initialize
      @body = Queue.new
      @finished = false
      @failed = false
      @body = []
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
      @on_chunk = block
      unless @body.empty?
        @body.each(&block)
        @body.clear
      end
    end

    # Returns the complete response body. Use #each_body instead if the body can be very large.
    # @return [String] the whole response body
    def body
      raise "Body already read" if @on_chunk
      if finished?
        @body.join
      else
        raise "Response body is not complete"
      end
    end

    # @api private
    def _headers(raw_headers)
      # response headers should not have duplicates
      @headers = raw_headers.to_h.freeze
    end

    # @api private
    def _chunk(chunk)
      if @on_chunk
        @on_chunk.call(chunk)
      else
        @body << chunk
      end
    end

    # @api private
    def _finish
      @finished = true
    end

    # @api private
    def _fail
      @failed = true
    end
  end
end
