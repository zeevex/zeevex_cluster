#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'pry'
require 'zeevex_cluster'
require 'zeevex_cluster/primitives'
require 'zeevex_cluster/coordinator'
require 'zeevex_cluster/coordinator/mysql'

require 'mysql2'

@client ||= Mysql2::Client.new(:host => 'localhost',
                               :database => 'zcluster',
                               :username => 'zcluster',
                               :password => 'zclusterp',
                               :reconnect => true,
                               :symbolize_keys => true,
                               :database_timezone => :utc)

$c = ZeevexCluster::Coordinator::Mysql.new :server => 'localhost',
                                           :port => 3306,
                                           :database => 'zcluster',
                                           :username => 'zcluster',
                                           :password => 'zclusterp',
                                           :nodename => 'repl',
                                           :expiration => 120
