require File.join(File.dirname(__FILE__), 'spec_helper')

describe ZeevexCluster::Unclustered do
  context 'creation' do
    it 'does not require any options' do
      expect { ZeevexCluster::Unclustered.new }.not_to raise_error(ArgumentError)
    end

    it 'accepts a specified nodename for self' do
      ZeevexCluster::Unclustered.new(:nodename => 'foobar').
          nodename.should == 'foobar'
    end

    it 'defaults to our hostname if nodename not specified' do
      ZeevexCluster::Unclustered.new.
          nodename.should == Socket.gethostname
    end

    it 'does not accept master nodename option' do
      expect { ZeevexCluster::Unclustered.new(:master_nodename => "foo") }.
          to raise_error(ArgumentError)
    end

    it 'should be subclass of Static cluster type' do
      ZeevexCluster::Unclustered.new.should be_a(ZeevexCluster::Static)
    end

    it 'should be master' do
      ZeevexCluster::Unclustered.new.master?.should be_true
    end
  end
end
