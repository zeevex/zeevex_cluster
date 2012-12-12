require 'rspec'

$: << File.expand_path(File.dirname(__FILE__) + '/../lib')
require 'zeevex_cluster'
require 'zeevex_cluster/static'
require 'zeevex_cluster/unclustered'
require 'zeevex_cluster/memcached'

require File.dirname(__FILE__) + '/shared_master_examples.rb'
require File.dirname(__FILE__) + '/shared_non_master_examples.rb'
require File.dirname(__FILE__) + '/shared_member_examples.rb'
