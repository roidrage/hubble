# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "hubble/version"

Gem::Specification.new do |s|
  s.name        = "hubble"
  s.email       = ["github.com"]
  s.version     = Hubble::VERSION
  s.authors     = ["GitHub Inc."]
  s.homepage    = "https://github.com/github/hubble"
  s.summary     = "Ruby client that posts to Haystack"
  s.description = "A simple ruby client for posting exceptions to Haystack"

  s.rubyforge_project = "hubble"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency "json",    "~> 1.6"
  s.add_dependency "faraday"

  s.add_development_dependency "rake", "~>0.8.7"
end
