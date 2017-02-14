require 'socket'
require 'openssl'
require 'epoll'

require_relative 'server_connection'
require_relative 'destination_connection'
require_relative 'dns_resolver'

class Agent
  attr_reader :epoll
  attr_reader :connections_by_socket
  attr_reader :dns_resolver

  def initialize
    @epoll = Epoll.create
    @connections_by_socket = {}
  end

  def run
    ServerConnection.new(self)
    @dns_resolver = DNSResolver.new(self)

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
