# -*- frozen-string-literal: true -*-
module Plum
  class Response
    attr_reader :headers

    def initialize
      @body = Queue.new
      @finished = false
      @body_read = false
    end

    def status
      @headers && @headers[":status"]
    end

    def finished?
      @finished
    end

    def each_body(&block)
      raise "Body already read" if @body_read
      @body_read = true
      while chunk = @body.pop
        yield chunk
      end
    end

    def body
      body = String.new
      each_body { |chunk| body << chunk }
      body
    end

    def _headers(raw_headers)
      # response headers should not have duplicates
      @headers = raw_headers.to_h
    end

    def _chunk(chunk)
      @body << chunk
    end

    def _finish
      @finished = true
      @body << nil # @body.close is not implemented in Ruby 2.2
    end
  end
end
