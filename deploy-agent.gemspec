# frozen_string_literal: true

require_relative 'lib/deploy_agent/version'

Gem::Specification.new do |s|
  s.name        = 'deploy-agent'
  s.version     = DeployAgent::VERSION
  s.required_ruby_version = '>= 2.7'
  s.summary     = 'The DeployHQ Agent'
  s.description = 'Deprecated: use https://github.com/deployhq/network-agent instead. ' \
                  'This gem allows you to configure a secure proxy through which DeployHQ can forward connections'
  s.authors     = ['Charlie Smurthwaite']
  s.email       = ['support@deployhq.com']
  s.files       = Dir.glob('{lib,bin}/**/*')
  s.files       << 'ca.crt'
  s.files       << 'deploy-agent.gemspec'
  s.homepage    = 'https://www.deployhq.com/'
  s.bindir      = 'bin'
  s.executables << 'deploy-agent'

  s.add_dependency 'nio4r', '~> 2.7'
  s.add_dependency 'rb-readline', '~> 0.5'
  # timers 4.4.0 raised required_ruby_version to >= 3.1. '~> 4.3' admits it, and the
  # RubyGems shipped with Ruby 2.7 cannot back off to 4.3.5 on its own, so a plain
  # `gem install deploy-agent` fails outright on every Ruby this gem still supports
  # below 3.1. Keep the upper bound until required_ruby_version moves past 3.1.
  s.add_dependency 'timers', '>= 4.3', '< 4.4'

  s.post_install_message = <<~MSG
    WARNING: deploy-agent is deprecated and only receives essential fixes.
    Please migrate to the new agent: https://github.com/deployhq/network-agent
  MSG
end
