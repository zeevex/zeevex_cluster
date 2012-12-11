shared_examples_for 'master_node' do
  it { should be_master }
  it 'should have the same nodename as the master' do
    subject.master.should == subject.nodename
  end
  it 'should execute run_if_master block' do
    subject.run_if_master do
      :ran
    end.should == :ran
  end
end
