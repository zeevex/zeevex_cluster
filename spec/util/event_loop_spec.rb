require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/event_loop.rb'

describe ZeevexCluster::Util::EventLoop do
  let :loop do
    ZeevexCluster::Util::EventLoop.new
  end
  before do
    loop.start
  end

  context 'basic usage' do
    it 'should allow enqueue of a proc' do
      loop.enqueue(Proc.new { true }).should be_a(ZeevexCluster::Util::EventLoop::Future)
    end

    it 'should allow enqueue of a block' do
      loop.enqueue do
        true
      end.should be_a(ZeevexCluster::Util::EventLoop::Future)
    end

    it 'should allow enqueue of a Future, and return same future' do
      future = ZeevexCluster::Util::EventLoop::Future.new(Proc.new {true})
      loop.enqueue(future).should == future
    end
  end

  context 'runs task asynchronously' do
    let :queue do
      Queue.new
    end

    it 'should execute the task on the event loop' do
      loop.enqueue { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should update the future only when ready' do
      res = loop.enqueue { queue.pop; "foo" }
      res.should_not be_ready
      queue << "go ahead"
      res.value.should == "foo"
    end
  end

  context 'on_event_loop' do
    let :queue do
      Queue.new
    end

    it 'should execute the task asynchronously from client code' do
      loop.on_event_loop { queue << Thread.current.__id__ }
      queue.pop.should_not == Thread.current.__id__
    end

    it 'should execute the task synchronously when called from event loop' do
      loop.enqueue do
        loop.on_event_loop { queue << "foo" }
        res = queue.pop
        queue << "done"
      end
      queue.pop.should == "done"
    end
  end
end

