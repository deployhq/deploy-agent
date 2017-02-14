class DestinationConnection
  def initialize(family, address, port, agent)
    @agent = agent
    @socket = Socket.new(family, Socket::Constants::SOCK_STREAM, 0)
    @agent.connections_by_socket[@socket] = self
    @id = @socket.to_i
    @sockaddr = Socket.sockaddr_in(port.to_i, address.to_s)
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
      rescue Errno::ECONNREFUSED
        # Send connection error
      end
      @status = :complete
    else
    end
  end
end
