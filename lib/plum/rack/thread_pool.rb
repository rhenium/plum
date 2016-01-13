# -*- frozen-string-literal: true -*-
module Plum
  module Rack
    class ThreadPool
      def initialize(size = 20)
        @workers = Set.new
        @jobs = Queue.new
        @tags = {}
        @cancels = Set.new
        @mutex = Mutex.new

        size.times { |i|
          spawn_worker
        }
      end

      # returns cancel token
      def acquire(tag = nil, err = nil, &blk)
        @jobs << [blk, err, tag]
        tag
      end

      def cancel(tag)
        worker = @mutex.synchronize { @tags.delete?(tag) || (@cancels << tag; return) }
        @workers.delete(worker)
        worker.kill
        spawn_worker
      end

      private
      def spawn_worker
        t = Thread.new {
          while true
            job, err, tag = @jobs.pop
            if tag
              next if @mutex.synchronize {
                c = @cancels.delete?(tag)
                @tags[tag] = self unless c
                c
              }
            end

            begin
              job.call
            rescue => e
              err << e if err
            end

            @mutex.synchronize { @tags.delete(tag) } if tag
          end
        }
        @workers << t
      end
    end
  end
end
