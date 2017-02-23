require 'socket'
require 'openssl'
require 'epoll'

require_relative 'server_connection'
require_relative 'destination_connection'

class Agent
  attr_reader :epoll
  attr_reader :connections_by_socket
  attr_reader :server_connection

  def initialize
    @epoll = Epoll.create
    @connections_by_socket = {}
  end

  def run
    @server_connection = ServerConnection.new(self, ARGV[0] || 'agent.deployhq.com')

    loop do
      evlist = epoll.wait
      evlist.each do |ev|
        # Data incoming
        if (ev.events & Epoll::IN) != 0
          @connections_by_socket[ev.data].receive_data
        end
        if (ev.events & Epoll::OUT) != 0
          @connections_by_socket[ev.data].send_buffer
        end
      end
    end
  end
end

Agent.new.run
