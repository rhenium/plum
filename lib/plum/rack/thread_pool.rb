# -*- frozen-string-literal: true -*-
module Plum
  module Rack
    class ThreadPool
      def initialize(size = 20)
        @workers = Set.new
        @jobs = Queue.new

        size.times { |i|
          spawn_worker
        }
      end

      # returns cancel token
      def acquire(tag = nil, err = nil, &blk)
        @jobs << [blk, err]
      end

      private
      def spawn_worker
        t = Thread.new {
          while true
            job, err = @jobs.pop
            begin
              job.call
            rescue => e
              err << e if err
            end
          end
        }
        @workers << t
      end
    end
  end
end
