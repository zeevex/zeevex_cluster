require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/util/delayed.rb'
require 'zeevex_cluster/util/promise.rb'
require 'zeevex_cluster/util/future.rb'

describe ZeevexCluster::Util::Delayed do
  clazz = ZeevexCluster::Util

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

