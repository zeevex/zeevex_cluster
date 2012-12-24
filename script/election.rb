#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), "../lib")
require 'rubygems'
require 'pry'
require 'zeevex_cluster'

ctype = ARGV[0] || 'memcached'
strategy_type = 'cas'

backend_options = case ctype
                    when 'memcached' then {:server => '127.0.0.1', :port => 11212}
                    when 'redis'     then {:server => '127.0.0.1', :port => 6379}
                    when 'mysql'     then {:server => '127.0.0.1', :port => 3306,
                                           :coordinator_options => {
                                               :namespace => 'cmdlinetest',
                                               :username => 'zcluster',
                                               :password => 'zclusterp',
                                               :database => 'zcluster'}
                                          }
                    when 'zookeeper'
                        strategy_type = 'zookeeper'
                        {}
                    else raise 'Must be memcached or redis or mysql'
                  end.
    merge({:coordinator_type => ctype})

$c = ZeevexCluster::Election.new :backend_options => backend_options,
                                 :cluster_name => 'foobs',
                                 :strategy_type => strategy_type,
                                 :nodename => "#{Socket.gethostname}:#{`tty`.chomp}",
                                 :logger => Logger.new(STDOUT),
                                 :hooks  => {:status_change => lambda {|who, news, olds, *rest|
                                                                       puts "MSC! #{news} #{olds}"} }

Pry.config.prompt = Pry::DEFAULT_PROMPT.clone
Pry.config.prompt[0] = proc do |target_self, nest_level, pry|
  cstatus = case true
              when $c.master? then "MASTER"
              when $c.member? then "member"
              else "offline"
            end
  mcount = $c.member? ? $c.members.count : 0
  "[#{pry.input_array.size}] #{cstatus}[#{mcount}] pry(#{Pry.view_clip(target_self)})#{":#{nest_level}" unless nest_level.zero?}> "
end

binding.pry
