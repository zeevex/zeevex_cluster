#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'pry'
require 'zeevex_cluster'
begin
require 'zeevex_cluster/primitives'
rescue LoadError
end

$s = ZeevexCluster::Serializer::JsonHash.new
$h = {:a_at => Time.now, :b => [Time.now], :c => {:timestamp => Time.now}}
