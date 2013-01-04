require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/event_loop.rb'

describe ZeevexCluster::Util::Future do
  clazz = ZeevexCluster::Util::Future

  context 'argument checking' do

    it 'should allow neither a callable nor a block' do
      expect { clazz.new }.
        not_to raise_error(ArgumentError)
    end

    it 'should not allow both a callable AND a block' do
      expect {
        clazz.new(Proc.new { 2 }) do
          1
        end
      }.to raise_error(ArgumentError)
    end

    it 'should accept a proc' do
      expect { clazz.new(Proc.new {}) }.
        not_to raise_error(ArgumentError)
    end

    it 'should accept a block' do
      expect {
        clazz.new do
          1
        end
      }.not_to raise_error(ArgumentError)
    end
  end


  context 'before receiving value' do
    subject { clazz.new() }
    it { should_not be_ready }

    ## queue.wait not available in ruby 1.8.7
    #it 'should wait for 2 seconds' do
    #  t_start = Time.now
    #  future.wait 10
    #  t_end = Time.now
    #  (t_end-t_start).should_be 10
    #end
  end

  context 'after using set_result' do
    subject { clazz.new(nil) }
    before do
      @counter = 55
      subject.set_result { @counter += 1 }
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
      clazz.new lambda {
        raise FooBar, "test"
      }
    end

    before do
      subject.execute
    end

    it { should be_ready }
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

  context 'observing' do
    subject { clazz.new(nil) }
    let :observer do
      mock()
    end

    it 'should notify observer after set_result' do
      observer.should_receive(:update)
      subject.add_observer observer
      subject.set_result { 10 }
    end

    it 'should notify observer after set_result raises exception' do
      observer.should_receive(:update)
      subject.add_observer observer
      subject.set_result { raise "foo" }
    end

    it 'should notify observer after #execute' do
      future = clazz.new(Proc.new { 4 + 20 })
      observer.should_receive(:update)
      future.add_observer observer
      future.execute
    end
  end
end

