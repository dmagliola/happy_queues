# We are moving towards having all async jobs running in latency based queues.
# From now on, all new jobs need to go into the "new", latency-based queues we've defined
# This cop will make sure we don't accidentally add new jobs to the "old" queues.
#
# The way to use this cop is to add it to your custom cops, and do a "one-time-only" addition
# of all offenders to `rubocop_todo.yml`. That way, all existing jobs will be "grandfathered in",
# but no new jobs will be allowed in the "old" queues.
module Cops
  class LatencyQueuesCop < RuboCop::Cop::Cop
    def_node_matcher :sidekiq_queue_name, <<~PATTERN
      (send nil? :sidekiq_options
        `(pair (sym :queue) (sym $_))
      )
    PATTERN

    def_node_matcher :active_job_queue_name, <<~PATTERN
      (send nil? :queue_as (sym $_) )
    PATTERN

    MSG = 'New async jobs should only use latency based queues'

    # TODO: Update this list with your *actual* queues,
    # or try a Regex-based approach, if you dare :-)
    LATENCY_BASED_QUEUES = %i[
      within_1_minute
      within_10_minutes
      within_1_hour
      within_1_day
    ].freeze

    def on_send(node)
      active_job_queue_name(node) do |name|
        next if LATENCY_BASED_QUEUES.include?(name)

        add_offense(node)
      end
      sidekiq_queue_name(node) do |name|
        next if LATENCY_BASED_QUEUES.include?(name)

        add_offense(node)
      end
    end
  end
end