gem 'nio4r', '2.1.0'
gem 'timers', '4.1.2'
require 'nio'
require 'timers'
require 'logger'

module DeployAgent
  class Agent
    def initialize(options = {})
      @retries = 0
      @options = options
    end

    def run
      logger.info("Running the deploy agent")
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

        @retries = 0
      end
    rescue OpenSSL::SSL::SSLError => e
      @retries += 1

      if @retries == 4
        raise e
      else
        retry
      end
    rescue ServerConnection::ServerDisconnected
      retry
    rescue Interrupt, SignalException => e
      logger.info("Stopping")
    rescue Exception => e
      logger.debug("#{e.class}: #{e.message}")
      raise e
    end

    def logger
      @logger ||= begin
        if $background
          logger = Logger.new(LOG_PATH, 5, 10240)
        else
          logger = Logger.new(STDOUT)
        end
        logger.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO
        logger
      end
    end

    private

    attr_reader :options
  end
end
