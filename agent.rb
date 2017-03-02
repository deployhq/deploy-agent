require 'socket'
require 'openssl'
require 'epoll'
require 'readline'
require 'net/https'
require 'json'

require_relative 'server_connection'
require_relative 'destination_connection'

class Agent
  attr_reader :epoll
  attr_reader :connections_by_socket
  attr_reader :server_connection

  def initialize
    @epoll = Epoll.create
    @connections_by_socket = {}
  end

  def run
    if File.exist?(ServerConnection::CERTIFICATE_PATH)
      @server_connection = ServerConnection.new(self, ARGV[1] || 'agent.deployhq.com')

      loop do
        evlist = epoll.wait
        evlist.each do |ev|
          # Data incoming
          if (ev.events & Epoll::IN) != 0
            @connections_by_socket[ev.data].receive_data
          end
          if (ev.events & Epoll::OUT) != 0
            @connections_by_socket[ev.data].send_buffer
          end
        end
      end
    else
      puts 'Certificate not found. Please run the following to generate a certificate.'
      puts
      puts ' # deploy-agent certificate'
      puts
    end
  end

  def self.generate_certificate
    puts 'This tool will assist you in generating a certificate for your Deploy agent.'
    puts
    puts 'Please enter a name for this agent'
    Readline.completion_proc = Proc.new {}
    begin
      str = Readline.readline("Agent Name: ", true)
    rescue Interrupt => e
      puts
      exit
    end
    if str.length < 2
      puts "Name must be at least 2 characters."
      exit
    else
      uri = certificate_uri
      Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Post.new uri
        request.body = {:name => str}.to_json
        request['Content-Type'] = 'application/json'
        response = http.request request
        puts JSON.parse(response.body).inspect
      end
    end
  end

  def self.certificate_uri
    URI(ARGV[1] || 'https://api.deployhq.com/api/v1/agents/create')
  end

end

case ARGV[0]
when 'run'
when 'run-foreground'
  Agent.new.run
when 'certificate'
  Agent.generate_certificate
when 'install'
end
