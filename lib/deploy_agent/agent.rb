gem 'nio4r', '2.1.0'
gem 'timers', '4.1.2'
require 'nio'
require 'timers'
require 'logger'

module DeployAgent
  class Agent

    def run
      nio_selector = NIO::Selector.new
      timers = Timers::Group.new
      target = ENV['DEPLOY_AGENT_PROXY_IP'] || 'agent.deployhq.com'
      server_connection = ServerConnection.new(self, target, nio_selector, !ENV['DEPLOY_AGENT_NOVERIFY'])
      timers.every(60) { server_connection.keepalive }
      loop do
        wait_interval = timers.wait_interval
        wait_interval = 0 if wait_interval < 0
        nio_selector.select(wait_interval) do |monitor|
          monitor.value.rx_data if monitor.readable?
          monitor.value.tx_data if monitor.writeable?
        end
        timers.fire
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
