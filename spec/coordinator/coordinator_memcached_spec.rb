require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/coordinator/memcached.rb'

describe ZeevexCluster::Coordinator::Memcached do
  let :mockery do
    mock()
  end

  let :clazz do
    ZeevexCluster::Coordinator::Memcached
  end

  let :default_options do
    {:server => '127.0.0.1', :expiration => 30, :namespace => "foo"}
  end

  context 'instantiation' do
    it 'requires server argument' do
      expect { clazz.new(:expiration => 30) }.
          to raise_error(ArgumentError)
    end
    it 'requires expiration argument' do
      expect { clazz.new(:server => '127.0.0.1') }.
          to raise_error(ArgumentError)
    end
    it 'constructs successfully with both args' do
      expect { clazz.new({:server => '127.0.0.1', :expiration => 30}) }.
          not_to raise_error
    end
  end

  context 'basic methods' do
    subject { clazz.new(default_options.merge(:client => mockery)) }
    it 'handles add' do
      mockery.should_receive(:add).with('foo:bar', 12, 30).and_return('STORED')
      subject.add('bar', 12).should == true
    end
    it 'handles set' do
      mockery.should_receive(:set).with('foo:bar', 13, 30).and_return('STORED')
      subject.set('bar', 13).should == true
    end
    it 'handles get' do
      mockery.should_receive(:get).with('foo:bar').and_return(14)
      subject.get('bar').should == 14
    end
  end

  context 'cas' do
    subject { clazz.new(default_options.merge(:client => mockery)) }

    it 'calls block with current value'
    it 'attempts to set new value'
    it 'fails if value has changed'
    it 'allows block to abort by raising exception'
  end
end
