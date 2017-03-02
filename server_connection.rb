require 'socket'
require 'ipaddr'

include Socket::Constants

# The ServerConnection class deals with all communication with the Deploy server
class ServerConnection
  CONFIG_PATH      = File.expand_path('~/.deploy')
  CERTIFICATE_PATH = File.expand_path('~/.deploy/agent.crt')
  KEY_PATH         = File.expand_path('~/.deploy/agent.key')
  CA_PATH          = File.expand_path('~/.deploy/ca.crt')

  # Create a secure TLS connection to the Deploy server
  def initialize(agent, server_host)
    @destination_connections = {}
    @agent = agent

    # Create a TCP socket to the Deploy server
    server_sock = TCPSocket.new(server_host, 7777)

    # Configure an OpenSSL context with server vertification
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # Load the agent certificate and key used to authenticate this agent
    ctx.cert = OpenSSL::X509::Certificate.new(File.read(CERTIFICATE_PATH))
    ctx.key = OpenSSL::PKey::RSA.new(File.read(KEY_PATH))
    # Load the Deploy CA used to verify the server
    ctx.ca_file = CA_PATH
    # Create the secure connection
    @socket = OpenSSL::SSL::SSLSocket.new(server_sock, ctx)
    @socket.connect
    # Check the remote certificate
    @socket.post_connection_check(server_host) unless server_host == '127.0.0.1'
    # Use epoll to wait for data from the server
    @agent.epoll.add(@socket, Epoll::IN)
    # Add this connection to the list of open sockets
    @agent.connections_by_socket[@socket] = self
    # Create send and receive buffers
    @send_buffer = String.new.force_encoding('BINARY')
    @buffer = String.new.force_encoding('BINARY')

    puts "Successfully connected to server"
  end

  # Receive and process packets from the control server
  def receive_data
    # Ensure all received data is read
    @buffer << @socket.readpartial(10240)
    while(@socket.pending > 0)
      @buffer << @socket.readpartial(10240)
    end
    # Wait until we have a complete packet of data
    while @buffer.bytesize >=2 && @buffer.bytesize >= @buffer[0,2].unpack('n')[0]
      length = @buffer[0,2].unpack('n')[0]
      # Extract the packet from the buffered stream
      packet = @buffer[2, length-2]
      @buffer = @buffer[length..-1]
      # Check what type of packet we have received
      case packet.bytes[0]
      when 1
        # Process new connection request
        id = packet[1,2].unpack('n')[0]
        host, port = packet[3..-1].split('/', 2)
        puts "[#{id}] Connect Request from server: #{host}:#{port}"
        begin
          # Create conenction to the final destination and save info by id
          @destination_connections[id] = DestinationConnection.new(host, port, @agent, id)
        rescue => e
          # Something went wrong, inform the Deploy server
          send_connection_error(id, e.message)
        end
      when 3
        # Process a connection close request
        id = packet[1,2].unpack('n')[0]
        puts "[#{id}] Close requested from server"
        @destination_connections[id].close
      when 4
        # Data incoming, send it to the backend
        id = packet[1,2].unpack('n')[0]
        puts "[#{id}] Data received from server"
        @destination_connections[id].send_data(packet[3..-1])
      end
    end
  rescue EOFError
    puts "Server disconnected"
    Process.exit(0)
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

  # Proxy data (coming from the backend) to the Deploy server
  def send_data(id, data)
    send_packet([4, id, data].pack('Cna*'))
  end

  # Called by event loop to send all waiting packets to the Deploy server
  def send_buffer
    bytes_sent = @socket.write_nonblock(@send_buffer)
    # Send as much data as possible
    if bytes_sent >= @send_buffer.bytesize
      @send_buffer = String.new.force_encoding('BINARY')
      @agent.epoll.mod(@socket, Epoll::IN)
    else
      # If we didn't manage to send all the data, leave
      # the remaining data in the send buffer
      @send_buffer = @send_buffer[bytes_sent..-1]
    end
  end

  private

  # Queue a packet of data to be sent to the Deploy server
  def send_packet(data)
    @send_buffer << [data.bytesize+2, data].pack('na*')
    @agent.epoll.mod(@socket, Epoll::IN|Epoll::OUT)
  end

end
