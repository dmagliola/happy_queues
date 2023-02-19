# Report metrics every time a job gets enqueued.
# We increment `sidekiq.job_enqueued` to count how many jobs of each type got enqueued.
#
# Needs to be added as Client Middleware to Sidekiq's chain, on both `configure_client` and
# `configure_server`, so we can pick up jobs enqueued by other jobs.
#
# If you have other client middleware that can stop jobs from getting pushed,
# you might want to ensure this middleware is added last, to avoid reporting
# enqueues that later get stopped.
module Sidekiq
  module Middleware
    class SidekiqEnqueueMetrics
      METRIC_NAME = 'sidekiq.job_enqueued'

      def call(worker_class, job, queue, _redis_pool, *)
        report_metrics(worker_class, job, queue)
        yield
      end

      private

      def report_metrics(worker_class, job, queue)
        tags = build_tags(worker_class, job, queue)
        STATSD.increment METRIC_NAME, tags: tags
      end

      def build_tags(worker_class, job, queue)
        [
          "name:#{job_name(worker_class, job)}",
          "queue:#{queue}"
        ]
      end

      # `worker_class` is the Worker Class directly, so we need to `.name` to get class name
      # This is subtly different from SidekiqExecutionMetrics, which gets a Worker instance
      # In some circumstances, though (apparently when enqueueing a scheduled job), it can be a string
      def job_name(worker_class, job)
        job_name = if job['wrapped'].present?
                     job['wrapped'].to_s # ActiveJob Wrapped class
                   elsif worker_class.is_a?(String)
                     # When enqueueing scheduled jobs (and possibly in other similar situations),
                     # `worker_class` may be a String.
                     worker_class
                   else
                     worker_class.name # Reference to the Actual Worker Class, get Class.name
                   end

        job_name.underscore
      end
    end
  end
end
