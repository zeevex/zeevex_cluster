require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/serializer/json_hash.rb'

describe ZeevexCluster::Serializer::JsonHash do
  let :serializer do
    ZeevexCluster::Serializer::JsonHash.new
  end

  context 'cas host tokens' do
    let :times do
      now = Time.at(1355418862)
      {:joined_at => now - 7200, :timestamp => now, :locked_at => now - 600}
    end

    let :hash do
      times.merge({:nodename => 'mynode'})
    end

    let :json do
      serializer.serialize(hash)
    end

    context 'serialized form' do
      subject { json }
      it { should be_a(String) }
      it { should match /"joined_at":\s*1355411662\.0/ }
      it { should match /"locked_at":\s*1355418262\.0/ }
      it { should match /"timestamp":\s*1355418862\.0/ }
      it { should match /"nodename":\s*"mynode"/ }
      it { should match /^\{.*\}$/ }
      it 'should be a valid JSON string' do
        JSON.parse(subject).should be_a(Hash)
      end
    end

    context 'deserialized hash' do
      subject { serializer.deserialize(json) }
      it { should have(4).keys }
      it { should == hash }
      it 'should have only symbol keys' do
        subject.keys.reject {|k| k.is_a?(Symbol) }.should be_empty
      end
      it 'should have 3 time fields' do
        subject.values.select {|key| key.is_a?(Time) }.should have(3).items
      end
      it 'should have matching times for 3 fields' do
        times.map {|(key, val)| subject[key].utc.should == val.utc }
      end
    end
  end
end

