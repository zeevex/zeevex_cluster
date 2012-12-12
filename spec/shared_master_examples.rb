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
  it 'should no longer be master after leaving' do
    expect { subject.leave }.
        to change { subject.master? }.
        from(true).to(false)
  end
  #it 'should resign before leaving the cluster' do
  #  subject.should_receive(:resign!).and_return(true)
  #  subject.leave
  #end
end
