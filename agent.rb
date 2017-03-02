require 'socket'
require 'openssl'
require 'epoll'
require 'readline'
require 'net/https'
require 'json'
require 'fileutils'

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
    puts 'Please enter a name for this agent.'
    Readline.completion_proc = Proc.new {}
    begin
      name = Readline.readline("Agent Name: ", true)
    rescue Interrupt => e
      puts
      exit
    end
    if name.length < 2
      puts "Name must be at least 2 characters."
      exit
    else
      uri = certificate_uri
      Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Post.new uri
        request.body = {:name => name}.to_json
        request['Content-Type'] = 'application/json'
        response = http.request request
        response_hash = JSON.parse(response.body)
        if response_hash['status'] == 'success'
          FileUtils.mkdir_p(ServerConnection::CONFIG_PATH)
          File.write(ServerConnection::CA_PATH,          response_hash['data']['ca'])
          File.write(ServerConnection::CERTIFICATE_PATH, response_hash['data']['certificate'])
          File.write(ServerConnection::KEY_PATH,         response_hash['data']['private_key'])
          puts
          puts "Certificate has been successfully generated and installed."
          puts
          puts "You can now associate this Agent with your Deploy account."
          puts "Browse to Settings -> Agents in your account and enter the code below:"
          puts
          puts " >> #{response_hash['data']['claim_code']} <<"
          puts
          puts "You can start the agent using the following command:"
          puts
          puts " # deploy-agent start"
          puts
        else
          puts
          puts "An error occurred obtaining a certificate."
          puts "Please contact support, quoting the debug information below:"
          puts
          puts response.inspect
          puts response.body
          puts
        end
      end
    end
  end

  def self.certificate_uri
    URI(ARGV[1] || 'https://api.deployhq.com/api/v1/agents/create')
  end

end

case ARGV[0]
when 'start'
when 'run'
  Agent.new.run
when 'certificate'
  Agent.generate_certificate
when 'install'
end
