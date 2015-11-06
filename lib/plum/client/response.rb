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
      @body_read = false
    end

    # Return the HTTP status code.
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

    # Yields a chunk of the response body until EOF.
    # @yield [chunk] A chunk of the response body.
    def each_chunk(&block)
      raise "Body already read" if @body_read
      @body_read = true
      while !(finished? && @body.empty?) && chunk = @body.pop
        if Exception === chunk
          raise chunk
        else
          yield chunk
        end
      end
    end

    # Returns the complete response body. Use #each_body instead if the body can be very large.
    # @return [String] the whole response body
    def body
      body = String.new
      each_chunk { |chunk| body << chunk }
      body
    end

    # @api private
    def _headers(raw_headers)
      # response headers should not have duplicates
      @headers = raw_headers.to_h.freeze
    end

    # @api private
    def _chunk(chunk)
      @body << chunk
    end

    # @api private
    def _finish
      @finished = true
      @body << nil # @body.close is not implemented in Ruby 2.2
    end

    # @api private
    def _fail(ex)
      @failed = true
      @body << ex
    end
  end
end
