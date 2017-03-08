gem 'nio4r', '1.2.1'
require 'nio'
require 'logger'

module DeployAgent
  class Agent

    def run
      nio_selector = NIO::Selector.new
      target = ENV['DEPLOY_AGENT_PROXY_IP'] || 'agent.deployhq.com'
      ServerConnection.new(self, target, nio_selector, !ENV['DEPLOY_AGENT_NOVERIFY'])

      loop do
        nio_selector.select do |monitor|
          monitor.value.rx_data if monitor.readable?
          monitor.value.tx_data if monitor.writeable?
        end
      end
    rescue ServerConnection::ServerDisconnected
      retry
    end

    def logger
      @logger ||= begin
        if $background
          logger = Logger.new(LOG_PATH, 5, 10240)
          logger.level = Logger::INFO
          logger
        else
          Logger.new(STDOUT)
        end
      end
    end

  end
end
