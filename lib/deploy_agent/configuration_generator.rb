gem 'rb-readline', '0.5.4'
require 'readline'
require 'net/https'
require 'json'
require 'fileutils'

module DeployAgent
  class ConfigurationGenerator
    attr_accessor :claim_code

    def configure
      if File.file?(CERTIFICATE_PATH) || File.file?(ACCESS_PATH)
        puts "***************************** WARNING *****************************"
        puts "The Deploy agent has already been configured. Are you sure you wish"
        puts "to remove the existing configuration and generate a new one?"
        puts

        response = ask("Remove existing configuration? [no]: ")
        Process.exit(1) unless response == 'yes'
        puts
      end

      generate_certificate
      generate_access_list

      puts
      puts "You can now associate this Agent with your Deploy account."
      puts "Browse to Settings -> Agents in your account and enter the code below:"
      puts
      puts " >> #{claim_code} <<"
      puts
      puts "You can start the agent using the following command:"
      puts
      puts " # deploy-agent start"
      puts
    end

    def generate_certificate
      puts 'This tool will assist you in generating a certificate for your Deploy agent.'
      puts 'Please enter a name for this agent.'

      name = ask("Agent Name: ")
      if name.length < 2
        puts "Name must be at least 2 characters."
        Process.exit(1)
      else
        uri = certificate_uri
        Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Post.new(uri)
          request.body = {:name => name}.to_json
          request['Content-Type'] = 'application/json'
          response = http.request request
          response_hash = JSON.parse(response.body)
          if response_hash['status'] == 'success'
            self.claim_code = response_hash['data']['claim_code']

            File.write(CERTIFICATE_PATH, response_hash['data']['certificate'])
            File.write(KEY_PATH,         response_hash['data']['private_key'])
            puts
            puts "Certificate has been successfully generated and installed."
            puts
          else
            puts
            puts "An error occurred obtaining a certificate."
            puts "Please contact support, quoting the debug information below:"
            puts
            puts response.inspect
            puts response.body
            puts
            Process.exit(1)
          end
        end
      end
    end

    def generate_access_list
      puts "By default this utility only allows connections from DeployHQ to localhost."
      puts "To to deploy to other hosts or networks enter their addresses below:\n"

      user_hosts = []
      loop do
        host = ask("IP Address [leave blank to finish]: ")
        if host.empty?
          break
        else
          user_hosts << host
        end
      end

      begin
        access_list = File.open(ACCESS_PATH, 'w')

        # Add header and localhost entries
        access_list.write("# This file contains a list of host and network addresses the Deploy agent\n# will allow connections to. Add IPs or networks (CIDR format) as needed.\n\n# Allow deployments to localhost\n127.0.0.1\n::1\n")

        # Add user entries (if any)
        access_list.write("\n# User defined destinations\n")
        user_hosts.each do |host|
          access_list.write("#{host}\n")
        end
      ensure
        access_list.close if access_list
      end
    end

    private

    def ask(question)
      Readline.completion_proc = Proc.new {}
      Readline.readline(question, true)
    rescue Interrupt => e
      puts
      Process.exit(1)
    end

    def certificate_uri
      URI(ENV['DEPLOY_AGENT_CERTIFICATE_URL'] || 'https://api.deployhq.com/api/v1/agents/create')
    end
  end
end
