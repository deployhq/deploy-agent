class AgentConnection
  COMMAND_CREATE_REQUEST = 1
  COMMAND_CREATE_RESPONSE = 2
  COMMAND_DESTROY = 3
  COMMAND_DATA = 4

  def initialize(agent_socket, cn, server)
    @cn = cn
    @agent_socket = agent_socket
    @buffer = String.new.force_encoding('BINARY')
    @send_buffer = String.new.force_encoding('BINARY')
    @server = server
    @client_connections = {}
    @id = 0
    puts "Agent Connected. CN: #{cn}"
  end

  def generate_id
    @id += 1
    @id = 1 if @id > 65535
    @id
  end

  def receive_data
    @buffer << @agent_socket.readpartial(10000)
    while @buffer.bytesize >=2 && @buffer.bytesize >= @buffer[0,2].unpack('n')[0]
      packet = @buffer[0, @buffer[0,2].unpack('n')[0]]
      @buffer = @buffer[@buffer[0,2].unpack('n')[0]..-1]
      process_packet(packet)
    end
  rescue EOFError, Errno::ECONNRESET
    close
  end

  def close
    @client_connections.values.each { |cc| cc.close }
    @server.clients_by_cn.delete_if{|_,v| v == self}
    @server.clients_by_socket.delete(@agent_socket)
    @server.epoll.del(@agent_socket)
    @agent_socket.close
  end

  # All packets will be in the following format
  # Length[2] Length of this packet in bytes including headers starting with this one
  # Command[1] The purpose of this packet
  # Data [L-3] Parameters, may be some integers or a string, or both
  def process_packet(packet)
    length, command, data = packet.unpack('nCa*')
    case command
    when COMMAND_DATA
      data(data)
    when COMMAND_CREATE_RESPONSE
      create_response(data)
    when COMMAND_DESTROY
      receive_destroy(data)
    end
  end

  def data(packet)
    id, data = packet.unpack('na*')
    @client_connections[id].send_data(data)
  end

  def create_connection(ip, port, client_connection)
    id = generate_id
    puts "[#{id}] Creating Connection through agent to #{ip}/#{port}"
    @client_connections[id] = client_connection
    send_packet([COMMAND_CREATE_REQUEST, id, "#{ip}/#{port}"].pack('Cna*'))
    return id
  end

  def create_response(data)
    id, status, reason = data.unpack('nCa*')
    case status
    when 0
      # Connection Success
      @client_connections[id].send_connect_success
    else
      # Connection Failed
      @client_connections[id].send_connect_fail(reason)
      @client_connections[id].close
    end
  end

  def receive_destroy(data)
    id = data.unpack('n')[0]
    puts "[#{id}] Received close request from agent"
    @client_connections[id].close
    @client_connections.delete(id)
  end

  def terminate_by_id(id)
    if @client_connections.delete(id)
      send_destroy(id)
    end
  end

  def send_destroy(id)
    puts "[#{id}] Sending close request to agent"
    send_packet([COMMAND_DESTROY, id].pack('Cn'))
  end

  def send_data(id, data)
    puts "[#{id}] Sending data to agent for connection"
    send_packet([COMMAND_DATA, id, data].pack('Cna*'))
  end

  def send_packet(data)
    @send_buffer << [data.bytesize+2, data].pack('na*')
    @server.epoll.mod(@agent_socket, Epoll::IN|Epoll::OUT)
  end

  def send_buffer
    bytes_sent = @agent_socket.write_nonblock(@send_buffer)
    if bytes_sent >= @send_buffer.bytesize
      @send_buffer = String.new.force_encoding('BINARY')
      @server.epoll.mod(@agent_socket, Epoll::IN)
    else
      @send_buffer = @send_buffer[bytes_sent..-1]
    end
  end
end
