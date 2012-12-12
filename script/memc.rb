#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'pry'
require 'zeevex_cluster'
require 'zeevex_cluster/memcached'

# ZeevexCluster.logger = Logger.new(STDOUT)
$c = ZeevexCluster::Memcached.new :server => '127.0.0.1', :port => 11212, :cluster_name => 'foobs',
                                  :nodename => "#{Socket.gethostname}:#{`tty`.chomp}",
                                  :logger => Logger.new(STDOUT),
                                  :hooks  => {:status_change => lambda {|who, news, olds, *rest| puts "MSC! #{news} #{olds}"} }

