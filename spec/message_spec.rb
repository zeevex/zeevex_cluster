require File.join(File.dirname(__FILE__), 'spec_helper')
require 'zeevex_cluster/message.rb'

#
# REQUIRED_KEYS = %w{source sequence sent_at expires_at contents content_type encoding}
#

describe ZeevexCluster::Message do
  subject { ZeevexCluster::Message.new :contents => '{foo: 1}', :source => 'node1' }

  context 'creation' do
    it { should be_a(Hash) }
    it { should have_key(:contents) }
    it { should have_key(:source) }
    it { should_not be_valid }

    context 'default values' do
      it { should have_key(:content_type) }
      its(:content_type) { should == 'application/json' }
      its(:encoding) { should be_nil }
    end
  end

  context 'method-style access' do
    it { should respond_to("contents") }
    its(:source) { should == 'node1' }
  end

  context 'validation' do
    it 'should not be valid without required keys' do
      subject.should_not be_valid
    end
    it 'should be valid if required keys are added' do
      subject.merge(:sequence => 1, :sent_at => Time.now, :expires_at => Time.now + 7200).should be_valid
    end
  end
end

