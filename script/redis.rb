#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'pry'
require 'zeevex_cluster'
require 'zeevex_cluster/coordinator/redis'

# ZeevexCluster.logger = Logger.new(STDOUT)
$c = ZeevexCluster::Coordinator::Redis.new :backend_options => {:server => '127.0.0.1', :port => 6379, :expiration => 120},
                                  :server => '127.0.0.1', :port => 6379, :expiration => 120,
                                  :cluster_name => 'foobs',
                                  :nodename => "#{Socket.gethostname}:#{`tty`.chomp}",
                                  :logger => Logger.new(STDOUT),
                                  :hooks  => {:status_change => lambda {|who, news, olds, *rest| puts "MSC! #{news} #{olds}"} }

