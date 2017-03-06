require 'nio'
require_relative('server_connection')

CONFIG_PATH      = File.expand_path('~/.deploy')
CERTIFICATE_PATH = File.expand_path('~/.deploy/agent.crt')
KEY_PATH         = File.expand_path('~/.deploy/agent.key')
CA_PATH          = File.expand_path('~/.deploy/ca.crt')

begin
  nio_selector = NIO::Selector.new
  ServerConnection.new('127.0.0.1', nio_selector, false)

  loop do
    nio_selector.select do |monitor|
      monitor.value.rx_data if monitor.readable?
      monitor.value.tx_data if monitor.writeable?
    end
  end
rescue ServerConnection::ServerDisconnected
  retry
end
