require 'test_helper'
require 'sidekiq'
require 'sidekiq/manager'

class ManagerTest < MiniTest::Unit::TestCase
  describe 'with redis' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
      @scheduler = SidekiqScheduler::Manager.new
      $processed = 0
      $mutex = Mutex.new
    end

    class IntegrationWorker
      include Sidekiq::Worker

      def perform(a, b)
        $mutex.synchronize do
          $processed += 1
        end
        a + b
      end
    end

    it 'detects an empty schedule run' do
      assert_nil @scheduler.wrapped_object.send(:find_next_timestamp)
    end

    it 'processes only jobs that are due' do
      timestamp = Time.now + 600
      Sidekiq::Client.delayed_push(:foo, timestamp, 'class' => IntegrationWorker, 'args' => [1,2])
      assert_nil @scheduler.wrapped_object.send(:find_next_timestamp)
    end

    it 'processes queues in the right order' do
      Sidekiq::Client.delayed_push(:foo, 1331284491, 'class' => IntegrationWorker, 'args' => [1,2])
      Sidekiq::Client.delayed_push(:foo, 1331284492, 'class' => IntegrationWorker, 'args' => [1,2])

      assert_equal 1331284491, @scheduler.wrapped_object.send(:find_next_timestamp)
    end

    it 'moves jobs from the scheduler queues to the worker queues' do
      Sidekiq::Client.delayed_push(:foo, 1331284491, 'class' => IntegrationWorker, 'args' => [1,2])

      @scheduler.wrapped_object.send(:find_scheduled_work, 1331284491)

      assert_equal 0, Sidekiq.redis {|c| c.llen("delayed:1331284491") }
      assert_equal 1, Sidekiq.redis {|c| c.llen("queue:foo") }
    end

    it 'resets the scheduler queue' do
      Sidekiq::Client.delayed_push(:foo, 1331284491, 'class' => IntegrationWorker, 'args' => [1,2])
      Sidekiq::Client.delayed_push(:foo, 1331284492, 'class' => IntegrationWorker, 'args' => [1,2])
      Sidekiq::Client.delayed_push(:foo, 1331284493, 'class' => IntegrationWorker, 'args' => [1,2])

      @scheduler.reset

      assert_equal 0, Sidekiq.redis {|c| c.zcard('delayed_queue_schedule') }
      assert !Sidekiq.redis {|c| c.exists('delayed:1331284491') }
      assert !Sidekiq.redis {|c| c.exists('delayed:1331284492') }
      assert !Sidekiq.redis {|c| c.exists('delayed:1331284493') }
    end
  end
end
