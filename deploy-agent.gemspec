# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'deploy-agent'
  s.version     = '1.3.3'
  s.required_ruby_version = '>= 2.7'
  s.summary     = 'The DeployHQ Agent'
  s.description = 'This gem allows you to configure a secure proxy through which DeployHQ can forward connections'
  s.authors     = ['Charlie Smurthwaite']
  s.email       = ['support@deployhq.com']
  s.files       = Dir.glob('{lib,bin}/**/*')
  s.files       << 'ca.crt'
  s.files       << 'deploy-agent.gemspec'
  s.homepage    = 'https://www.deployhq.com/'
  s.bindir      = 'bin'
  s.executables << 'deploy-agent'

  s.add_dependency 'nio4r', '2.1.0'
  s.add_dependency 'rb-readline', '0.5.5'
  s.add_dependency 'timers', '4.1.2'
end
