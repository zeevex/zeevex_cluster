require File.join(File.dirname(__FILE__), 'spec_helper')

describe ZeevexCluster::Static do
  def new_cluster(options = {})
    ZeevexCluster::Static.new({:master_nodename => :self}.merge(options))
  end

  context 'creation' do
    it 'requires the specification of a master nodename' do
      expect { ZeevexCluster::Static.new }.to raise_error(ArgumentError)
    end

    it 'accepts a specified nodename for self' do
      ZeevexCluster::Static.new(:nodename => 'foobar', :master_nodename => 'baz').
          nodename.should == 'foobar'
    end

    it 'defaults to our hostname if nodename not specified' do
      ZeevexCluster::Static.new(:master_nodename => 'baz').
          nodename.should == Socket.gethostname
    end

    it 'treats master nodename == :self as our own nodename' do
      ZeevexCluster::Static.new(:nodename => 'foo', :master_nodename => :self).
          master.should == 'foo'
    end
  end

  context 'when this node is specified as master' do
    def new_cluster(options = {})
      options[:master_nodename] = :self
      super
    end
    subject { ZeevexCluster::Static.new(:nodename => 'foo', :master_nodename => 'foo') }
    it_should_behave_like 'master_node'
    it_should_behave_like 'member_node'
  end

  context 'when this node is not specified as master' do
    def new_cluster(options = {})
      options[:master_nodename] = 'other'
      super
    end
    subject { ZeevexCluster::Static.new(:nodename => 'foo', :master_nodename => 'bar') }
    it_should_behave_like 'non_master_node'
    it_should_behave_like 'member_node'
  end

end
