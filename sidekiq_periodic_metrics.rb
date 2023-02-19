# Periodically exports metrics about the current state of our Sidekiq queues
#
# NOTE: This is written to work with Sidekiq and Datadog/STATSD, but the main ideas will
# still apply and should be easily adapted for any other queue and metrics systems combination.
#
# sidekiq.queue.size: Number of jobs in the queue.
# sidekiq.queue.latency: How late jobs are executing. i.e "how far behind" (in seconds) we are.
# sidekiq.queue.normalized_latency: What percentage (0.0 to 1.0) of the queue's latency SLO
#   we are at. Values over 1.0 mean we've broken our SLO.
#
# All metrics are tagged with `queue:{queue_name}`
class SidekiqQueuesJob
  DEFAULT_PERMITTED_LATENCY = 1.hour

  # TODO: Modify this hash with your actual queue names, and SLOs!
  QUEUES_PERMITTED_LATENCY = {
    within1minute: 1.minute,
    within10minutes: 10.minutes,
    within1hour: 1.hour,
    within1day: 1.day,
    within1day_high_memory: 1.day
  }.freeze

  def perform
    Sidekiq::Queue.all.each do |queue|
      tags = ["queue:#{queue.name}"]
      STATSD.gauge('sidekiq.queue.size', queue.size, tags: tags)
      STATSD.gauge('sidekiq.queue.latency', queue.latency, tags: tags)
      STATSD.gauge('sidekiq.queue.normalised_latency', normalised_latency(queue), tags: tags)
    end
  end

  private

  def normalised_latency(queue)
    metric = queue.latency.to_f / permitted_latency(queue)
    metric.round(3)
  end

  def permitted_latency(queue)
    QUEUES_PERMITTED_LATENCY.fetch(queue.name.to_sym, DEFAULT_PERMITTED_LATENCY)
  end
end
