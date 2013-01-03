require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/event_loop.rb'

describe ZeevexCluster::Util::Future do
  clazz = ZeevexCluster::Util::Future


  context 'before receiving value' do
    subject { clazz.new(nil) }
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
end

