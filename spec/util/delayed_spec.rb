require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/delayed.rb'
require 'zeevex_cluster/util/promise.rb'
require 'zeevex_cluster/util/future.rb'

describe ZeevexCluster::Util::Delayed do
  clazz = ZeevexCluster::Util

  context 'creation' do
    context '#promise' do
      it 'should create a promise with a block' do
        clazz.promise do
        end.should be_a(ZeevexCluster::Util::Promise)
      end

      it 'should create a promise with no arg or block' do
        clazz.promise.should be_a(ZeevexCluster::Util::Promise)
      end
    end

    context '#future' do
      it 'should create a future' do
        clazz.future do
        end.should be_a(ZeevexCluster::Util::Future)
      end
    end

    context '#delay' do
      it 'should create a promise given a block' do
        clazz.delay do
        end.should be_a(ZeevexCluster::Util::Promise)
      end
    end
  end

  context 'typing' do
    let :efuture do
      ZeevexCluster::Util.future(Proc.new {})
    end
    let :epromise do 
      ZeevexCluster::Util.promise(Proc.new {})
    end
    let :eproc do
      Proc.new {}
    end
    context '#delayed?' do
      it 'should be true for a promise' do
        clazz.delayed?(epromise).should be_true
      end
      it 'should be true for a future' do
        clazz.delayed?(efuture).should be_true
      end
      it 'should not be true for a proc' do
        clazz.delayed?(eproc).should be_false
      end
    end

    context '#future?' do
      it 'should be true for a future' do
        clazz.future?(efuture).should be_true
      end

      it 'should be false for a promise' do
        clazz.future?(epromise).should be_false
      end
    end

    context '#promise?' do
      it 'should be true for a promise' do
        clazz.promise?(epromise).should be_true
      end
      it 'should be false for a future' do
        clazz.promise?(efuture).should be_false
      end
    end
  end
end

