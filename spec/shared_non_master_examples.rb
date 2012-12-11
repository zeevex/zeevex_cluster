shared_examples_for 'non_master_node' do
  it { should_not be_master }
  it 'should not execute run_if_master block' do
    subject.run_if_master do
      :ran
    end.should == false
  end
end
