require 'deploy_agent/certificate_manager'
require 'deploy_agent/server_connection'
require 'deploy_agent/destination_connection'
require 'deploy_agent/cli'
require 'deploy_agent/agent'

module DeployAgent
  CONFIG_PATH      = File.expand_path('~/.deploy')
  CERTIFICATE_PATH = File.expand_path('~/.deploy/agent.crt')
  KEY_PATH         = File.expand_path('~/.deploy/agent.key')
  CA_PATH          = File.expand_path('~/.deploy/ca.crt')
  PID_PATH         = File.expand_path('~/.deploy/agent.pid')
  LOG_PATH         = File.expand_path('~/.deploy/agent.log')
end
