class ClientConnection
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
  end

  def receive_data
    case @state
    when :new
      # For a new connection, receive data until we have a complete connection request
      @buffer << @client_socket.readpartial(10000)
      if @buffer.bytesize >=2 && @buffer.bytesize >= @buffer[0,2].unpack('n')[0]
        # Process the connection request
        packet = @buffer[2, @buffer[0,2].unpack('n')[0]-2]
        @buffer = @buffer[@buffer[0,2].unpack('n')[0]..-1]
        agent_cn, ip, port = packet.split('/', 3)
        agent_connection = @server.clients_by_cn[agent_cn]
        agent_connection.create_connection(ip, port, self)
      end
    end
  rescue EOFError
    close
  end

  def close
    @server.clients_by_socket.delete(@client_socket)
    @server.epoll.del(@client_socket)
    @client_socket.close
  end
end
