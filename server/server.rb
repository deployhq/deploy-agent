require 'socket'
require 'epoll'
require 'openssl'

require_relative 'agent_connection'
require_relative 'client_connection'

class Server
  attr_reader :clients_by_cn
  attr_reader :clients_by_socket
  attr_reader :epoll

  def initialize
    @clients_by_socket = {}
    @clients_by_cn = {}
    @epoll = Epoll.create
  end

  def run
    Thread.new{status}
    agent_server_socket = TCPServer.new(7777)
    client_server_socket = TCPServer.new(7766)
    sslContext = OpenSSL::SSL::SSLContext.new
    sslContext.cert = OpenSSL::X509::Certificate.new(File.read("certificate.pem"))
    sslContext.key = OpenSSL::PKey::RSA.new(File.read("key.pem"))
    sslContext.verify_mode = OpenSSL::SSL::VERIFY_PEER
    sslContext.ca_file = "ca.pem"
    ssl_server_socket = OpenSSL::SSL::SSLServer.new(agent_server_socket, sslContext)

    @epoll.add(ssl_server_socket, Epoll::IN)
    @epoll.add(client_server_socket, Epoll::IN)

    loop do
      evlist = @epoll.wait
      evlist.each do |ev|
        if ev.data == ssl_server_socket
          begin
            # New agent incoming
            client_socket = ev.data.accept
            dn = client_socket.peer_cert.subject.to_a.each_with_object({}) do |i,h|
              h[i[0]] = i[1]
            end
            client = AgentConnection.new(client_socket, dn['CN'], self)
            @clients_by_socket[client_socket] = client
            @clients_by_cn[dn['CN']] = client
            @epoll.add(client_socket, Epoll::IN)
          rescue OpenSSL::SSL::SSLError
            client_socket.close if client_socket and !client_socket.closed?
          end
        elsif ev.data == client_server_socket
          # New client incoming
          client_socket = ev.data.accept
          client = ClientConnection.new(client_socket, self)
          @clients_by_socket[client_socket] = client
          @epoll.add(client_socket, Epoll::IN)
        else
          # Data incoming
          if (ev.events & Epoll::IN) != 0
            @clients_by_socket[ev.data].receive_data
          end
          if (ev.events & Epoll::OUT) != 0
            @clients_by_socket[ev.data].send_buffer
          end
        end
      end
    end
  end

end

Server.new.run
