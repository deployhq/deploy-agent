require 'deploy_agent/configuration_generator'
require 'deploy_agent/server_connection'
require 'deploy_agent/destination_connection'
require 'deploy_agent/cli'
require 'deploy_agent/agent'
require 'rubygems'

module DeployAgent
  CONFIG_PATH      = File.expand_path('~/.deploy')
  CERTIFICATE_PATH = File.expand_path('~/.deploy/agent.crt')
  KEY_PATH         = File.expand_path('~/.deploy/agent.key')
  PID_PATH         = File.expand_path('~/.deploy/agent.pid')
  LOG_PATH         = File.expand_path('~/.deploy/agent.log')
  ACCESS_PATH      = File.expand_path('~/.deploy/agent.access')
  CA_PATH          = File.expand_path('../../ca.crt', __FILE__)
  VERSION          = Gem::Specification::load("deploy-agent.gemspec").version

  def self.allowed_destinations
      destinations = File.read(ACCESS_PATH)
      destinations = destinations.split(/\n/).map(&:strip)
      destinations = destinations.reject { |n| n == '' || n[0] == '#' }
      destinations = destinations.map { |l| l.split(' ', 2)[0] }
      return destinations
  end
end
