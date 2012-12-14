#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'rubygems'
require 'pry'
require 'zeevex_cluster'

ctype = ARGV[0] || 'memcached'
backend_options = case ctype
                    when 'memcached' then {:server => '127.0.0.1', :port => 11212}
                    when 'redis'     then {:server => '127.0.0.1', :port => 6379}
                    else raise 'Must be memcached or redis'
                  end.
    merge({:coordinator_type => ctype})

$c = ZeevexCluster::Election.new :backend_options => backend_options,
                                 :cluster_name => 'foobs',
                                 :nodename => "#{Socket.gethostname}:#{`tty`.chomp}",
                                 :logger => Logger.new(STDOUT),
                                 :hooks  => {:status_change => lambda {|who, news, olds, *rest|
                                                                       puts "MSC! #{news} #{olds}"} }

binding.pry
