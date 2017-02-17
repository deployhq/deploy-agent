class DestinationConnection
  def initialize(host, port, agent, id)
    @agent = agent
    ipaddr = IPAddr.new(host)
    if ipaddr.ipv4?
      @socket = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
    else
      @socket = Socket.new(Socket::Constants::AF_INET6, Socket::Constants::SOCK_STREAM, 0)
    end
    @agent.connections_by_socket[@socket] = self
    @id = id
    @sockaddr = Socket.sockaddr_in(port.to_i, host.to_s)
    begin
      @status = :connecting
      @socket.connect_nonblock(@sockaddr)
    rescue IO::WaitWritable
      @agent.epoll.add(@socket, Epoll::OUT)
    end
  end

  def send_buffer
    # This might get called when there's data to send, but also
    # when a connections completes or fails.
    if @status == :connecting
      begin
        @socket.connect_nonblock(@sockaddr)
      rescue IO::WaitWritable
        puts "huh?"
        return
      rescue => e
        # Send connection error
        @agent.epoll.del(@socket)
        @socket.close
        @agent.server_connection.send_connection_error(@id, e.message.to_s)
        return
      end
      @agent.server_connection.send_connection_success(@id)
      @status = :complete
    else
    end
  end
end
