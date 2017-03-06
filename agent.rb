require 'nio'
require 'readline'
require 'net/https'
require 'json'
require 'fileutils'
require_relative('server_connection')

class Agent
  CONFIG_PATH      = File.expand_path('~/.deploy')
  CERTIFICATE_PATH = File.expand_path('~/.deploy/agent.crt')
  KEY_PATH         = File.expand_path('~/.deploy/agent.key')
  CA_PATH          = File.expand_path('~/.deploy/ca.crt')

  def self.run_server
    nio_selector = NIO::Selector.new
    ServerConnection.new(ARGV[1] || 'agent.deployhq.com', nio_selector, !ARGV[1])

    loop do
      nio_selector.select do |monitor|
        monitor.value.rx_data if monitor.readable?
        monitor.value.tx_data if monitor.writeable?
      end
    end
  rescue ServerConnection::ServerDisconnected
    retry
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
          FileUtils.mkdir_p(CONFIG_PATH)
          File.write(CA_PATH,          response_hash['data']['ca'])
          File.write(CERTIFICATE_PATH, response_hash['data']['certificate'])
          File.write(KEY_PATH,         response_hash['data']['private_key'])
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
  Agent.run_server
when 'config'
  Agent.generate_certificate
when 'install'
end
