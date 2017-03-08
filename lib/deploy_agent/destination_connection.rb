module DeployAgent
  # The DestinationConnection class managea a connection to a backend server
  class DestinationConnection
    attr_reader :socket

    # Create a connection to a backend server
    def initialize(host, port, id, nio_selector, server_connection)
      @agent = server_connection.agent
      @id = id
      @nio_selector = nio_selector
      @server_connection = server_connection

      # Check the IP address and create a socket
      ipaddr = IPAddr.new(host)
      if ipaddr.ipv4?
        @tcp_socket = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
      else
        @tcp_socket = Socket.new(Socket::Constants::AF_INET6, Socket::Constants::SOCK_STREAM, 0)
      end
      # Begin the connection attempt in the background
      @sockaddr = Socket.sockaddr_in(port.to_i, host.to_s)
      begin
        @tcp_socket.connect_nonblock(@sockaddr)
        # We don't expect to get here, but it's OK if we do
        @status = :connected
        @nio_monitor = @nio_selector.register(@tcp_socket, :r)
      rescue IO::WaitWritable
        # This is expected, we will get a callback when the connection completes
        @status = :connecting
        @nio_monitor = @nio_selector.register(@tcp_socket, :w)
      end
      @nio_monitor.value = self

      # Set up a send buffer
      @tx_buffer = String.new.force_encoding('BINARY')
    end

    # Queue data to be send to the backend
    def send_data(data)
      @tx_buffer << data
      @nio_monitor.interests = :rw
    end

    def tx_data
      # This might get called when there's data to send, but also
      # when a connections completes or fails.
      if @status == :connecting
        begin
          @tcp_socket.connect_nonblock(@sockaddr)
        rescue IO::WaitWritable
          # This shouldn't happen. If it does, ignore it and
          # wait a bit longer until the connection completes
          return
        rescue => e
          @agent.logger.info "[#{@id}] Connection failed: #{e.message.to_s}"
          # Something went wrong connecting, inform the Deploy Server
          close
          @server_connection.send_connection_error(@id, e.message.to_s)
          return
        end
          @agent.logger.info "[#{@id}] Connected to destination"
        @server_connection.send_connection_success(@id)
        @status = :connected
      end
      if @status == :connected && @tx_buffer.bytesize > 0
        bytes_sent = @tcp_socket.write_nonblock(@tx_buffer)
        if bytes_sent >= @tx_buffer.bytesize
          @tx_buffer = String.new.force_encoding('BINARY')
        else
          @tx_buffer = @tx_buffer[bytes_sent..-1]
        end
      end
      if @status == :connected && @tx_buffer.bytesize == 0
        # Nothing more to send, wait for inbound data only
        @nio_monitor.interests = :r
      end
    rescue Errno::ECONNRESET
      # The backend has closed the connection. Inform the Deploy server.
      @server_connection.send_connection_close(@id)
      # Ensure everything is tidied up
      close
    end

    def rx_data
      # Received data from backend. Pass this along to the Deploy server
      data = @tcp_socket.readpartial(10240)
      @agent.logger.debug "[#{@id}] #{data.bytesize} bytes received from destination"
      @server_connection.send_data(@id, data)
    rescue EOFError, Errno::ECONNRESET
      @agent.logger.info "[#{@id}] Destination closed connection"
      # The backend has closed the connection. Inform the Deploy server.
      @server_connection.send_connection_close(@id)
      # Ensure everything is tidied up
      close
    end

    def close
      @nio_selector.deregister(@tcp_socket)
      @server_connection.destination_connections.delete(@id)
      @tcp_socket.close
    end

  end
end
