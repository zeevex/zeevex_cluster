# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "zeevex_cluster/version"

Gem::Specification.new do |s|
  s.name        = "zeevex_cluster"
  s.version     = ZeevexCluster::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Robert Sanders"]
  s.email       = ["robert@zeevex.com"]
  s.homepage    = "http://github.com/zeevex/zeevex_cluster"
  s.summary     = %q{Use a shared service to reliably elect a master in a cluster of processes.}
  s.description = %q{Using a shared data storage service like MySQL, Memcache, Redis etc., one process of many can be elected a cluster master.}

  s.rubyforge_project = "zeevex_cluster"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'state_machine'
  s.add_dependency 'json'

  s.add_development_dependency 'rspec', '~> 2.9.0'
  s.add_development_dependency 'rake'

  s.add_development_dependency 'memcache-client', '> 1.7.0'
  s.add_development_dependency 'redis'
  s.add_development_dependency 'mysql2'
end
