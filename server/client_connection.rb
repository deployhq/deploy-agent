require 'securerandom'
require 'digest'

class ClientConnection
  # The client connection is very simple. When a connection is initially made,
  # a destination address and port are send to the server in the form:
  # Length[2] - length of this message in bytes (length of destination + 2)
  # Destination[N] - a string in the frm "CN/HOST/PORT"

  # A response is sent back to the client in the form:
  # Length[2] - length of this message in bytes (length of error message + 3)
  # Status[1] - 0=success 1=error
  # Error message[n]
  def initialize(client_socket, server)
    # The TCP connection with this client
    @client_socket = client_socket

    # A buffer of incoming data from this client
    @buffer = String.new.force_encoding('BINARY')

    # A buffer of outgoing data to this client
    @send_buffer = String.new.force_encoding('BINARY')

    # The server that created me
    @server = server

    # The agent connection to which this client is attached
    @agent_connection = nil

    # The state of this connection
    @state = :new

    # Generare a nonce and send to the client
    @nonce = SecureRandom.hex(20)
    @client_socket.write(@nonce)

    # Calculate the correct authentication response for this nonce using the PSK
    @correct_auth = Digest::SHA1.hexdigest(@nonce + @server.psk)
  end

  def receive_data
    @buffer << @client_socket.readpartial(10000)
    if @state == :new
      # For a new connection, receive data until we have a complete connection request
      if @buffer.bytesize >=42 && @buffer.bytesize >= 40 + @buffer[40,2].unpack('n')[0]
        # Extract the signature
        auth_response = @buffer.slice!(0..39)
        unless auth_response == @correct_auth
          send_connect_fail("Incorrect PSK")
          return close
        end
        # Process the connection request
        packet = @buffer[2, @buffer[0,2].unpack('n')[0]-2]
        @buffer = @buffer[@buffer[0,2].unpack('n')[0]..-1]
        agent_cn, ip, port = packet.split('/', 3)
        if @agent_connection = @server.clients_by_cn[agent_cn]
          @id = @agent_connection.create_connection(ip, port, self)
          @state = :connected
        else
          send_connect_fail("Agent not available")
          return close
        end
      end
    end
    if @buffer.bytesize > 0 && @state == :connected
      # There's some real data in the buffer
      @agent_connection.send_data(@id, @buffer)
      @buffer = String.new.force_encoding('BINARY')
    end
  rescue EOFError
    close
  end

  def send_data(data)
    @send_buffer << data
    @server.epoll.mod(@client_socket, Epoll::IN | Epoll::OUT)
  end

  def send_buffer
    bytes_sent = @client_socket.write_nonblock(@send_buffer)
    if bytes_sent >= @send_buffer.bytesize
      @send_buffer = String.new.force_encoding('BINARY')
      @server.epoll.mod(@client_socket, Epoll::IN)
    else
      @send_buffer = @send_buffer[bytes_sent..-1]
    end
  end

  def send_connect_success
    @client_socket.write([3, 0].pack('nC'))
  end

  def send_connect_fail(reason)
    @client_socket.write([reason.bytesize+3, 1, reason].pack('nCa*'))
  end

  def close
    @agent_connection.terminate_by_id(@id) if @id
    @server.clients_by_socket.delete(@client_socket)
    @server.epoll.del(@client_socket)
    @client_socket.close
  end
end
