require File.join(File.dirname(__FILE__), 'spec_helper')

describe ZeevexCluster::Unclustered do
  context 'creation' do
    it 'accepts a specified nodename for self' do
      ZeevexCluster::Unclustered.new(:nodename => 'foobar').
          nodename.should == 'foobar'
    end

    it 'defaults to our hostname if nodename not specified' do
      ZeevexCluster::Unclustered.new.
          nodename.should == Socket.gethostname
    end

    it 'treats master nodename == :self as our own nodename' do
      ZeevexCluster::Unclustered.new(:nodename => 'foo', :master_nodename => :self).
          master.should == 'foo'
    end
  end

  context 'as sole lord and master' do
    subject { ZeevexCluster::Unclustered.new }
    it_should_behave_like 'master_node'
  end

end
