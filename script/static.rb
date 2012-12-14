#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'rubygems'
require 'pry'
require 'zeevex_cluster'
require 'zeevex_cluster/election'
require 'zeevex_cluster/strategy/static'
require 'zeevex_cluster/strategy/unclustered'

# ZeevexCluster.logger = Logger.new(STDOUT)
ctype = ARGV[0] || 'memcached'
mname = ARGV[1] || 'none'
nodename = ARGV[2] || "#{Socket.gethostname}:#{`tty`.chomp}"

if mname == 'self'
  mname = nodename
end

backend_options = case ctype
                    when 'static' then {:master_nodename => mname}
                    when 'unclustered' then {}
                    else raise 'Must be static or unclustered'
                  end.merge(:nodename => nodename)

strategy = ZeevexCluster::Strategy.const_get(ctype.capitalize).new backend_options

$c = ZeevexCluster::Election.new :backend_options => backend_options,
                                 :strategy => strategy,
                                 :cluster_name => 'foobs',
                                 :nodename => nodename,
                                 :logger => Logger.new(STDOUT),
                                 :hooks  => {:status_change => lambda {|who, news, olds, *rest| puts "MSC! #{news} #{olds}"} }

binding.pry
