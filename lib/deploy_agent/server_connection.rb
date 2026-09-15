require 'socket'
require 'ipaddr'
require 'openssl'

module DeployAgent
  # The ServerConnection class deals with all communication with the Deploy server
  class ServerConnection
    class ServerDisconnected < StandardError;end
    attr_reader :destination_connections, :agent
    attr_writer :nio_monitor

    # Tunnel commands. 1-7 are the original proxy protocol. 8 and 9 were added
    # for in-band certificate renewal and are implemented identically in the Go
    # agent (network-agent) and in the backend.
    COMMAND_RENEW_REQUEST  = 8 # agent -> server, payload "ruby/<version>"
    COMMAND_RENEW_RESPONSE = 9 # server -> agent, payload [status:1][body]

    # COMMAND_RENEW_RESPONSE statuses
    RENEW_STATUS_RENEWED = 0 # body is the replacement certificate, PEM encoded
    RENEW_STATUS_CURRENT = 1 # no body, the certificate we hold is current
    RENEW_STATUS_ERROR   = 2 # body is a UTF-8 message

    # Create a secure TLS connection to the Deploy server
    def initialize(agent, server_host, nio_selector, check_certificate=true)
      @agent = agent
      @agent.logger.info "Attempting to connect to #{server_host}"
      @destination_connections = {}
      @nio_selector = nio_selector

      # Create a TCP socket to the Deploy server
      @tcp_socket = TCPSocket.new(server_host, 7777)

      # Configure an OpenSSL context with server vertification
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = check_certificate ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      # Load the agent certificate and key used to authenticate this agent
      ctx.cert = OpenSSL::X509::Certificate.new(File.read(CERTIFICATE_PATH))
      ctx.key = OpenSSL::PKey::RSA.new(File.read(KEY_PATH))
      # Load the Deploy CA used to verify the server
      ctx.ca_file = CA_PATH

      # Create the secure connection
      @socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, ctx)
      @socket.connect
      # Check the remote certificate
      @socket.post_connection_check(server_host) if check_certificate
      # Create send and receive buffers
      @tx_buffer = String.new.force_encoding('BINARY')
      @rx_buffer = String.new.force_encoding('BINARY')

      @nio_monitor = @nio_selector.register(@tcp_socket, :r)
      @nio_monitor.value = self

      # Ask the server whether a replacement certificate is waiting for us. The
      # server decides and answers with COMMAND_RENEW_RESPONSE; it never sends one
      # unsolicited. This has to come after the monitor exists because send_packet
      # arms it for writing.
      request_certificate_renewal

      @agent.logger.info "Successfully connected to server"
    rescue => e
      @agent.logger.info "Something went wrong connecting to server."
      # Sleep between 10 and 20 seconds
      random_sleep = rand(10) + 10
      @agent.logger.info "#{e.to_s} #{e.message}"
      @agent.logger.info "Retrying in #{random_sleep} seconds."
      sleep random_sleep
      retry
    end

    # Receive and process packets from the control server
    def rx_data
      # Ensure all received data is read
      loop do
        begin
          data = @socket.read_nonblock(10240)
          raise EOFError if data.nil?

          @rx_buffer << data
        rescue IO::WaitReadable, IO::WaitWritable
          break # nothing more to read
        end
      end

      # Wait until we have a complete packet of data
      while @rx_buffer.bytesize >=2 && @rx_buffer.bytesize >= @rx_buffer[0,2].unpack('n')[0]
        length = @rx_buffer.slice!(0,2).unpack('n')[0]
        # Extract the packet from the buffered stream
        packet = @rx_buffer.slice!(0,length-2)
        # Check what type of packet we have received
        case packet.bytes[0]
        when 1
          # Process new connection request
          id = packet[1,2].unpack('n')[0]
          host, port = packet[3..-1].split('/', 2)
          @agent.logger.info "[#{id}] Connection request from server: #{host}:#{port}"
          return send_connection_error(id, "Destination address not allowed") unless destination_allowed?(host)

          begin
            # Create conenction to the final destination and save info by id
            @destination_connections[id] = DestinationConnection.new(host, port, id, @nio_selector, self)
          rescue => e
            # Something went wrong, inform the Deploy server
            @agent.logger.error "An error occurred: #{e.message}"
            @agent.logger.error e.backtrace
            send_connection_error(id, e.message)
          end
        when 3
          # Process a connection close request
          id = packet[1,2].unpack('n')[0]
          if @destination_connections[id]
            @agent.logger.info "[#{id}] Close requested by server, closing"
            @destination_connections[id].close
          else
            @agent.logger.info "[#{id}] Close requested by server, not open"
          end
        when 4
          # Data incoming, send it to the backend
          id = packet[1,2].unpack('n')[0]
          @agent.logger.debug "[#{id}] #{packet.bytesize} bytes received from server"
          @destination_connections[id].send_data(packet[3..-1])
        when 5
          # This is a shutdown request. Disconnect and don't re-attempt connection.
          @agent.logger.warn "Server rejected connection. Shutting down."
          @agent.logger.warn packet[1..-1]
          Process.exit(0)
        when 6
          # This is a shutdown request. Disconnect and don't re-attempt connection.
          @agent.logger.warn "Server requested reconnect. Closing connection."
          close
        when COMMAND_RENEW_RESPONSE
          # The server has answered our renewal request.
          handle_renewal_response(packet[1..-1])
        end
      end
    rescue EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETRESET
      close
    end

    def destination_allowed?(destination)
      return false unless File.file?(ACCESS_PATH)
      DeployAgent.allowed_destinations.each do |network|
        begin
          return true if IPAddr.new(network).include?(destination)
        rescue IPAddr::InvalidAddressError
          # Not a valid IP or netmask, deny and continue
        end
      end
      false
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
    def tx_data
      @agent.logger.debug('Writing to socket')
      bytes_sent = @socket.write_nonblock(@tx_buffer[0,1024])
      @agent.logger.debug('Writing to socket completed')
      # Send as much data as possible
      if bytes_sent >= @tx_buffer.bytesize
        @tx_buffer = String.new.force_encoding('BINARY')
        @nio_monitor.interests = :r
      else
        # If we didn't manage to send all the data, leave
        # the remaining data in the send buffer
        @tx_buffer.slice!(0, bytes_sent)
      end
    rescue EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETRESET
      close
    end

    def keepalive
      @agent.logger.debug "Sending keepalive"
      send_packet([7].pack('C'))
    end

    private

    def close
      @agent.logger.info "Server disconnected, terminating all connections"
      @destination_connections.values.each{ |s| s.close }
      @nio_selector.deregister(@tcp_socket)
      @socket.close
      @tcp_socket.close
      raise ServerDisconnected
    end

    # Ask the server to re-issue our client certificate, telling it which agent
    # implementation and version is asking. Renewal is best effort: it must never
    # stop us connecting, so a failure here is logged and otherwise ignored.
    def request_certificate_renewal
      @agent.logger.debug "Requesting certificate renewal"
      send_packet([COMMAND_RENEW_REQUEST, "ruby/#{DeployAgent::VERSION}"].pack('Ca*'))
    rescue => e
      @agent.logger.warn "Could not request certificate renewal: #{e.message}"
    end

    # Process a COMMAND_RENEW_RESPONSE. Renewal must never take the agent down, so
    # anything unexpected is logged and the existing certificate is kept.
    def handle_renewal_response(body)
      body = body.to_s
      status = body.bytes[0]
      payload = body[1..-1].to_s

      case status
      when RENEW_STATUS_RENEWED
        certificate = CertificateRenewal.new.install(payload)
        if certificate
          @agent.logger.info "Certificate renewed (issuer=#{certificate.issuer})"
          # Reconnect so the new certificate is the one we present. close raises
          # ServerDisconnected, which Agent#run catches and retries, and the new
          # connection re-reads agent.crt from disk.
          close
        else
          @agent.logger.debug "Server offered the certificate we already hold"
        end
      when RENEW_STATUS_CURRENT
        @agent.logger.debug "Certificate is up to date"
      when RENEW_STATUS_ERROR
        @agent.logger.warn "Server could not renew our certificate: #{payload}"
      else
        @agent.logger.warn "Unknown certificate renewal status: #{status.inspect}"
      end
    rescue ServerDisconnected
      raise
    rescue => e
      @agent.logger.warn "Certificate renewal failed: #{e.message}"
    end

    # Queue a packet of data to be sent to the Deploy server
    def send_packet(data)
      @tx_buffer << [data.bytesize+2, data].pack('na*')
      @nio_monitor.interests = :rw
    end

  end
end
