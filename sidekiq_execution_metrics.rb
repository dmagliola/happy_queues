# Report metrics for every job run.
# We report:
#   - `sidekiq.job` to count how many times each job has run
#   - `sidekiq.job.time` (StatsD timing) for stats on job runtime.
#   - `sidekiq.job.total_time` (counter! In Seconds!) Total time spent working on the job.
#        We need this because StatsD timing is great for averages, but doesn't give us an
#        accurate way to get the total time we spent working on a job / queue.
#        We can approximate it if we do `time.avg * time.count`, but that's less accurate, and it
#        only works if we're grouping by job. We can't get "total time for a queue", for example.
#
# Needs to be added as Server Middleware to Sidekiq's chain, on `configure_server`.
#
# This used to be inside the sidekiq-datadog gem, but we've inlined it as it didn't do
# that much, and the code and setup is much simpler if we don't need to make it configurable.
# And most importantly, we want to add some custom functionality for ourselves here.
module Sidekiq
  module Middleware
    class JobExecutionMetrics
      METRIC_NAME = 'sidekiq.job'

      def call(worker, job, queue, *)
        start_clock = process_clock
        begin
          yield
          report_metrics(worker, job, queue, start_clock)
        rescue StandardError => e
          report_metrics(worker, job, queue, start_clock, e)
          raise
        end
      end

      private

      def report_metrics(worker, job, queue, start_clock, error = nil)
        duration_ms = process_clock - start_clock
        tags = build_tags(worker, job, queue, error)

        STATSD.increment METRIC_NAME, tags: tags
        STATSD.timing "#{METRIC_NAME}.time", duration_ms, tags: tags
        STATSD.increment "#{METRIC_NAME}.total_time", by: (duration_ms / 1000.0), tags: tags
      end

      def build_tags(worker, job, queue, error)
        tags = []

        tags.push "name:#{job_name(worker, job)}"
        tags.push "queue:#{queue}" if queue

        if error.nil?
          tags.push 'status:ok'
        else
          kind = error.class.name.underscore
          tags.push 'status:error'
          tags.push "error:#{kind}"
        end

        tags
      end

      # `worker` is an **instance** of the Worker Class, so we need to `.class.to_s` to get class name
      # This is subtly different from SidekiqEnqueueMetrics, which gets a Worker class
      def job_name(worker, job)
        job_name = (job['wrapped'].present? ? job['wrapped'].to_s : worker.class.to_s)
        job_name.underscore
      end

      def process_clock
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end
  end
end
