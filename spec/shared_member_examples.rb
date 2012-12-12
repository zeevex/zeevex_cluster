#
# depends on a couple of let bindings
#
#  - autojoined:     newly created, autojoined
#  - non_autojoined: newly created, autojoin => false
#
# and a method:
#
#  - new_cluster(options)
#
shared_examples_for 'member_node' do
  context 'when auto-joined' do
    subject { new_cluster(:autojoin => true) }

    it { should be_member }

    it 'should have a nodename' do
      subject.nodename.should_not be_nil
      subject.nodename.should_not be_empty
    end

    it 'should become non-member after leaving' do
      expect { subject.leave }.
          to change { subject.member? }.from(true).to(false)
    end
  end

  context 'when not auto-joined' do
    subject { new_cluster(:autojoin => false) }

    it { should_not be_member }

    it 'should become member after joining' do
      expect { subject.join }.
          to change { subject.member? }.from(false).to(true)
    end
  end

end
