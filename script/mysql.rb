#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'pry'
require 'zeevex_cluster'
require 'zeevex_cluster/unclustered'
require 'zeevex_cluster/static'
require 'zeevex_cluster/primitives'

require 'mysql2'

@client ||= Mysql2::Client.new(:host => 'localhost',
                               :database => 'zcluster',
                               :username => 'zcluster',
                               :password => 'zclusterp',
                               :reconnect => true)
