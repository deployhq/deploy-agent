require 'socket'
include Socket::Constants

class ServerConnection
  def initialize(agent)
    @agent = agent
    server_sock = TCPSocket.new('127.0.0.1', 7777)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = OpenSSL::X509::Certificate.new(File.read("certificate.pem"))
    ctx.key = OpenSSL::PKey::RSA.new(File.read("key.pem"))
    @socket = OpenSSL::SSL::SSLSocket.new(server_sock, ctx)
    @socket.connect
    @agent.epoll.add(@socket, Epoll::IN)
    @agent.connections_by_socket[@socket] = self
    @buffer = String.new.force_encoding('BINARY')
    @send_buffer = String.new.force_encoding('BINARY')
  end

  def receive_data
    # Process packets from server
    @buffer << @socket.readpartial(10240)
    while(@socket.pending > 0)
      @buffer << @socket.readpartial(10240)
    end
    while @buffer.bytesize >=2 && @buffer.bytesize >= @buffer[0,2].unpack('n')[0]
      length = @buffer[0,2].unpack('n')[0]
      packet = @buffer[2, length-2]
      @buffer = @buffer[length..-1]
      case packet.bytes[0]
      when 1
        # New connection
        host, port = packet[1..-1].split('/', 2)
        puts "Connect Request: #{host}:#{port}"
        @agent.dns_resolver.resolve(host) do |status, family, address|
          puts "got answer from dns: #{status}, #{family}, #{address}"
          if status
            DestinationConnection.new(family, address, port, @agent)
          else
            # Respond with DNS error
          end
        end
      end
    end
  end

  def send_data
    @send_buffer << [data.bytesize+2, data].pack('na*')
    @server.epoll.mod(@client_socket, Epoll::IN|Epoll::OUT)
  end

  def send_buffer
    bytes_sent = @socket.write_nonblock(@send_buffer)
    if bytes_sent >= @send_buffer.bytesize
      @send_buffer = String.new.force_encoding('BINARY')
      @server.epoll.mod(@socket, Epoll::IN)
    else
      @send_buffer = @send_buffer[bytes_sent..-1]
    end
  end

end
