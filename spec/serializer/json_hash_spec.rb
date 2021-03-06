require File.join(File.dirname(__FILE__), '../spec_helper')
require 'zeevex_cluster/serializer/json_hash.rb'

describe ZeevexCluster::Serializer::JsonHash do
  let :serializer do
    ZeevexCluster::Serializer::JsonHash.new
  end

  context 'cas host tokens' do
    let :now do
      Time.at(1355418862)
    end
    let :times do
      {:joined_at => now - 7200, :timestamp => now, :locked_at => now - 600}
    end

    let :nodehash do
      times.merge({:nodename => 'mynode'})
    end

    let :json do
      serializer.serialize(nodehash)
    end

    context 'serialized form' do
      subject { json }
      it { should be_a(String) }
      it { should match /"joined_at":\{[^}]*1355411662/ }
      it { should match /"locked_at":\{[^}]*1355418262/ }
      it { should match /"timestamp":\{[^}]*1355418862/ }
      it { should match /"nodename":\s*"mynode"/ }
      it { should match /^\{.*\}$/ }
      it 'should be a valid JSON string' do
        JSON.parse(subject).should be_a(Hash)
      end
    end

    context 'deserialized hash' do
      subject { serializer.deserialize(json) }
      it { should have(4).keys }
      it { should == nodehash }
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

    context 'nested hashes' do
      let :innerhash do
        {:when => now - 7200, :members => ["a", "b"]}
      end

      let :tophash do
        {:mlist => innerhash, :timestamp => now}
      end

      it 'should roundtrip' do
        serializer.deserialize( serializer.serialize(tophash) ).should == tophash
      end
    end
  end
end

