require 'socket'
require 'resolv'

class DNSResolver
  def initialize(agent)
    @agent = agent
    @socket = UDPSocket.new
    @agent.epoll.add(@socket, Epoll::IN)
    @agent.connections_by_socket[@socket] = self
    @requests = {}
    @id = 0
  end

  def generate_id
    @id = @id + 1
    if @id > 65535
      @id = 1
    end
    @id
  end

  def resolve(address, &block)
    # TODO: DNS Timeout
    nameserver = nameservers[0]
    id = generate_id
    msg = Resolv::DNS::Message.new
    msg.id = id
    msg.rd = 1
    msg.add_question address, Resolv::DNS::Resource::IN::A
    @socket.send(msg.encode, 0, nameserver[0], nameserver[1])
    @requests[id] = block
  end

  def nameservers
    config_hash = ::Resolv::DNS::Config.default_config_hash
    if config_hash.include? :nameserver
      config_hash[:nameserver].map { |ns| [ ns, 53 ] }
    elsif config_hash.include? :nameserver_port
      config_hash[:nameserver_port]
    else
      [ '0.0.0.0', 53 ]
    end
  end

  def receive_data
    data = @socket.recv(1500)
    msg = Resolv::DNS::Message.decode(data)
    req = @requests.delete(msg.id)
    msg.each_answer do |name,ttl,data|
      case data
      when Resolv::DNS::Resource::IN::A
        return req.call(true, Socket::Constants::AF_INET, data.address.to_s)
      end
    end
    req.call(false, nil, nil)
  end

end
