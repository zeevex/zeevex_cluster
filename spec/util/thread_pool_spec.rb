require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/thread_pool.rb'
require 'zeevex_cluster/util/event_loop.rb'
require 'timeout'

describe ZeevexCluster::Util::ThreadPool do

  shared_examples_for 'thread pool initialization' do
    context 'basic usage' do
      it 'should allow enqueue of a proc' do
        expect { pool.enqueue(Proc.new { true }) }.
            not_to raise_error
      end

      it 'should allow enqueue of a block' do
        expect {
          pool.enqueue do
            true
          end
        }.not_to raise_error
      end

      it 'should allow enqueue of a Promise, and return same promise' do
        promise = ZeevexCluster::Util::Promise.new(Proc.new {true})
        expect { pool.enqueue(promise) }.not_to raise_error
      end

      it 'should NOT allow both a callable and a block' do
        expect {
          pool.enqueue(Proc.new{}) do
            true
          end
        }.to raise_error(ArgumentError)
      end
    end
  end

  shared_examples_for 'thread pool running tasks' do
    let :queue do
      Queue.new
    end

    it 'should execute the task on a different thread' do
      pool.enqueue { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should allow enqueueing from an executed task, and execute both' do
      pool.enqueue do
        pool.enqueue { queue << "val2" }
        queue << "val1"
      end
      [queue.pop, queue.pop].sort.should == ["val1", "val2"]
    end
  end

  shared_examples_for 'thread pool control' do
    let :queue do
      Queue.new
    end

    it 'should allow enqueueing after a stop/start' do
      pool.stop
      pool.start
      pool.enqueue do
        queue << "ran"
      end
      Timeout::timeout(5) do
        queue.pop.should == "ran"
      end
    end
  end

  context 'FixedPool' do
    let :pool do
      ZeevexCluster::Util::ThreadPool::FixedPool.new
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
  end

  context 'InlineThreadPool' do
    let :pool do
      ZeevexCluster::Util::ThreadPool::InlineThreadPool.new
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
  end

  context 'ThreadPerJobPool' do
    let :pool do
      ZeevexCluster::Util::ThreadPool::ThreadPerJobPool.new
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
  end

  context 'EventLoopAdapter' do
    let :loop do
      ZeevexCluster::Util::EventLoop.new
    end
    let :pool do
      ZeevexCluster::Util::ThreadPool::EventLoopAdapter.new loop
    end

    it_should_behave_like 'thread pool initialization'
    it_should_behave_like 'thread pool running tasks'
    it_should_behave_like 'thread pool control'
  end

end

