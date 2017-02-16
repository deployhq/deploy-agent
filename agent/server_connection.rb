require 'socket'
include Socket::Constants

# The ServerConnection class deals with all communication with the control server
class ServerConnection
  # Create a secure connection to the control server
  def initialize(agent)
    @backend_connections = {}
    @agent = agent
    server_sock = TCPSocket.new('127.0.0.1', 7777)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = OpenSSL::X509::Certificate.new(File.read("certificate.pem"))
    ctx.key = OpenSSL::PKey::RSA.new(File.read("key.pem"))
    ctx.ca_file = "ca.pem"
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    @socket = OpenSSL::SSL::SSLSocket.new(server_sock, ctx)
    @socket.connect
    @agent.epoll.add(@socket, Epoll::IN)
    @agent.connections_by_socket[@socket] = self
    @buffer = String.new.force_encoding('BINARY')
    @send_buffer = String.new.force_encoding('BINARY')
  end

  # Receive and process packets from the control server
  def receive_data
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
        id = packet[1,2].unpack('n')[0]
        host, port = packet[3..-1].split('/', 2)
        puts "Connect Request: #{host}:#{port}"
        @agent.dns_resolver.resolve(host) do |status, family, address|
          puts "got answer from dns: #{status}, #{family}, #{address}"
          if status
            DestinationConnection.new(family, address, port, @agent, id)
          else
            send_connection_error(id, "DNS Lookup Failed")
          end
        end
      when 4
        # Terminate connection
        id = packet[1,2].unpack('n')[0]
        backend_connections[id].destroy
      end
    end
  end

  # Notify server of successful connection
  def send_connection_success(id)
    send_packet([2, id, 0].pack('CnC'))
  end

  # Notify server of failed connection
  def send_connection_error(id, reason)
    send_packet([2, id, 1, reason].pack('CnCa*'))
  end

  # Notify server of closed connection
  def send_connection_close(id)
    send_packet([3, id].pack('Cn'))
  end

  # Proxy connection data to the server
  def send_data(id, data)
    send_packet([4, id, data].pack('Cna*'))
  end

  # Called by event loop to send all waiting packets to the server
  def send_buffer
    bytes_sent = @socket.write_nonblock(@send_buffer)
    if bytes_sent >= @send_buffer.bytesize
      @send_buffer = String.new.force_encoding('BINARY')
      @agent.epoll.mod(@socket, Epoll::IN)
    else
      @send_buffer = @send_buffer[bytes_sent..-1]
    end
  end

  private

  # Send a packet of data to the server
  def send_packet(data)
    @send_buffer << [data.bytesize+2, data].pack('na*')
    @agent.epoll.mod(@socket, Epoll::IN|Epoll::OUT)
  end

end
