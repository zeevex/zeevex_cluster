require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/coordinator/memcached.rb'

describe ZeevexCluster::Coordinator::Memcached do
  STORED = "STORED\r\n"
  EXISTS = "EXISTS\r\n"
  
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
      mockery.should_receive(:add).with('foo:bar', '12', 30, true).and_return(STORED)
      subject.add('bar', 12).should == true
    end
    it 'handles set' do
      mockery.should_receive(:set).with('foo:bar', '13', 30, true).and_return(STORED)
      subject.set('bar', 13).should == true
    end
    it 'handles get' do
      mockery.should_receive(:get).with('foo:bar', true).and_return('14')
      subject.get('bar').should == 14
    end
  end

  context 'cas' do
    subject { clazz.new(default_options.merge(:client => mockery)) }
    let :blok do
      Proc.new do |value|
        value
        @block_called = true
      end
    end

    it 'delegates with correct arguments' do
      mockery.should_receive(:cas).with('foo:bar', 45, true).and_return(STORED)
      subject.cas('bar', :expiration => 45) {|val|}
    end

    it 'calls block with current value and receive new value' do
      mockery.should_receive(:cas) do |key, expiration, raw, &block|
        block.should_not be_nil
        block.call('"yeeha"').should == '"yeehayeeha"'
        STORED
      end
      subject.cas('bar', :expiration => 45) do |val|
        @block_called = true
        val + val
      end
      @block_called.should be_true
    end

    it 'allows block to abort with no change to value' do
      mockery.stub(:cas) do |*args, &block|
        block.call '7'
      end
      subject.cas('bar') do |val|
        raise ZeevexCluster::Coordinator::DontChange
      end.should == false
    end

    it 'return nil if cas failed due to no key' do
      mockery.should_receive(:cas).and_return(nil)
      subject.cas('bar') {|val|}.should be_nil
    end

    it 'return true if cas succeeded' do
      mockery.should_receive(:cas).and_return(STORED)
      subject.cas('bar') {|val|}.should be_true
    end

    it 'return false if cas conflicted' do
      mockery.should_receive(:cas).and_return(EXISTS)
      subject.cas('bar') {|val|}.should be_false
    end
  end
end
