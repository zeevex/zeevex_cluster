require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/future.rb'
require 'zeevex_cluster/util/event_loop.rb'

describe ZeevexCluster::Util::Future do
  clazz = ZeevexCluster::Util::Future

  let :empty_proc do
    Proc.new { 8800 }
  end

  let :sleep_proc do
    Proc.new { sleep 60 }
  end

  let :queue do
    Queue.new
  end

  before :each do
    loop = ZeevexCluster::Util::EventLoop.new
    loop.start
    # oldloop = ZeevexCluster::Util::Future.class_eval do
    #   @@event_loop
    # end
    # Thread.new { oldloop.stop }
    ZeevexCluster::Util::Future.worker_pool = loop
  end

  context 'argument checking' do
    it 'should require a callable or a block' do
      expect { clazz.create }.
        to raise_error(ArgumentError)
    end

    it 'should not allow both a callable AND a block' do
      expect {
        clazz.create(empty_proc) do
          1
        end
      }.to raise_error(ArgumentError)
    end

    it 'should accept a proc' do
      expect { clazz.create(empty_proc) }.
        not_to raise_error(ArgumentError)
    end

    it 'should accept a block' do
      expect {
        clazz.create do
          1
        end
      }.not_to raise_error(ArgumentError)
    end
  end

  context 'before receiving value' do
    subject { clazz.create(sleep_proc) }
    it { should_not be_ready }
  end

  context 'after executing' do
    subject {
      clazz.create do
        @counter += 1
      end
    }

    before do
      @counter = 55
      subject.wait
    end

    it          { should be_ready }
    its(:value) { should == 56 }
    it 'should return same value for repeated calls' do
      subject.value
      subject.value.should == 56
    end
  end

  context 'with exception' do
    class FooBar < StandardError; end
    subject do
      clazz.create do
        # binding.pry
        raise FooBar, "test"
      end
    end

    before do
      subject.wait
    end

    it 'should be ready' do
      subject.should be_ready
    end
    
    it 'should reraise exception' do
      expect { subject.value }.
        to raise_error(FooBar)
    end

    it 'should optionally not reraise' do
      expect { subject.value(false) }.
        not_to raise_error(FooBar)
      subject.value(false).should be_a(FooBar)
    end
  end

  context '#wait' do
    subject { clazz.create(Proc.new { queue.pop }) }
    it 'should wait for 2 seconds' do
      t_start = Time.now
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 2
      res.should be_false
    end

    it 'should return immediately if ready' do
      t_start = Time.now
      queue << 99
      res = subject.wait 2
      t_end = Time.now
      (t_end-t_start).round.should == 0
      res.should be_true
    end
  end

  context 'observing' do
    subject { clazz.create(Proc.new { queue.pop; @callable.call }, :observer => observer) }
    let :observer do
      mock()
    end

    it 'should notify observer after set_result' do
      @callable = Proc.new { 10 }
      observer.should_receive(:update).with(subject, 10, true)
      queue << 1
      subject.wait
    end

    it 'should notify observer after set_result raises exception' do
      @callable = Proc.new { raise "foo" }
      observer.should_receive(:update).with(subject, kind_of(Exception), false)
      queue << 1
      subject.wait
    end
  end

  context 'access from multiple threads' do

    let :delay_queue do
      Queue.new
    end

    let :future do
      clazz.create(Proc.new { delay_queue.pop; @value += 1})
    end

    before do
      @value = 20
      future
      threads = []
      5.times do
        threads << Thread.new do
          queue << future.value
        end
      end
      Thread.pass
      @queue_size_before_set = queue.size
      delay_queue << "proceed"
      threads.map &:join
    end

    it 'should block all threads before set_result' do
      @queue_size_before_set.should == 0
    end

    it 'should allow all threads to receive a value' do
      queue.size.should == 5
    end

    it 'should only evaluate the computation once' do
      @value.should == 21
    end

    it 'should send the same value to all threads' do
      list = []
      5.times { list << queue.pop }
      list.should == [21,21,21,21,21]
    end
  end
end

