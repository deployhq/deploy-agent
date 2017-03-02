# The DestinationConnection class managea a connection to a backend server
class DestinationConnection

  # Create a connection to a backend server
  def initialize(host, port, agent, id)
    @agent = agent
    @id = id
    # Check the IP address and create a socket
    ipaddr = IPAddr.new(host)
    if ipaddr.ipv4?
      @socket = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
    else
      @socket = Socket.new(Socket::Constants::AF_INET6, Socket::Constants::SOCK_STREAM, 0)
    end
    # Save this socket so it can be found later when data arrives
    @agent.connections_by_socket[@socket] = self

    # Begin the connection attempt in the background
    @sockaddr = Socket.sockaddr_in(port.to_i, host.to_s)
    begin
      @status = :connecting
      @socket.connect_nonblock(@sockaddr)
    rescue IO::WaitWritable
      @agent.epoll.add(@socket, Epoll::OUT)
    end
    # Set up a send buffer
    @send_buffer = String.new.force_encoding('BINARY')
  end

  # Queue data to be send to the backend
  def send_data(data)
    @send_buffer << data
    @agent.epoll.mod(@socket, Epoll::IN | Epoll::OUT)
  end

  def send_buffer
    # This might get called when there's data to send, but also
    # when a connections completes or fails.
    if @status == :connecting
      begin
        @socket.connect_nonblock(@sockaddr)
      rescue IO::WaitWritable
        # This shouldn't happen. If it does, ignore it and
        # wait a bit longer until the connection completes
        return
      rescue => e
        # Something went wrong connecting, inform the Deploy Server
        close
        @agent.server_connection.send_connection_error(@id, e.message.to_s)
        return
      end
      @agent.server_connection.send_connection_success(@id)
      @status = :complete
    end
    if @status == :complete && @send_buffer.bytesize > 0
      bytes_sent = @socket.write_nonblock(@send_buffer)
      if bytes_sent >= @send_buffer.bytesize
        @send_buffer = String.new.force_encoding('BINARY')
        @agent.epoll.mod(@socket, Epoll::IN)
      else
        @send_buffer = @send_buffer[bytes_sent..-1]
      end
    end
  end

  def receive_data
    # Received data from backend. Pass this along to the Deploy server
    puts "[#{@id}] Received data from destination"
    @agent.server_connection.send_data(@id, @socket.readpartial(10240))
  rescue EOFError, Errno::ECONNRESET
    # The backend has closed the connection. Inform the Deploy server.
    @agent.server_connection.send_connection_close(@id)
    # Ensure everything is tidied up
    close
  end

  def close
    @agent.connections_by_socket.delete(@socket)
    unless @socket.closed?
      @agent.epoll.del(@socket)
      @socket.close
    end
  end

end
