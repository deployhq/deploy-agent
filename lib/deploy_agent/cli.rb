require 'ipaddr'
require 'optparse'

module DeployAgent
  class CLI

    def dispatch(arguments)
      methods = self.public_methods(false).delete_if { |n| n == :dispatch }.sort

      @options = {}

      OptionParser.new do |opts|
        opts.on('-v', '--verbose', 'Log extra debug information') do
          @options[:verbose] = true
        end
      end.parse!(arguments)

      if arguments[0] && methods.include?(arguments[0].to_sym)
        public_send(arguments[0])
      else
        puts "Usage: deploy-agent [#{methods.join('|')}]"
      end
    end

    def setup
      ConfigurationGenerator.new.configure
    end

    def restart
      stop
      while(is_running?)
        sleep 0.5
      end
      start
    end

    def start
      if is_running?
        puts "Deploy agent already running. Process ID #{pid_from_file}"
        Process.exit(1)
      else
        ensure_configured
        pid = fork do
          $background = true
          write_pid
          run
        end
        puts "Deploy agent started. Process ID #{pid}"
        Process.detach(pid)
      end
    end

    def stop
      if is_running?
        pid = pid_from_file
        Process.kill('TERM', pid)
        puts "Deploy agent stopped. Process ID #{pid}"
      else
        puts "Deploy agent is not running"
        Process.exit(1)
      end
    end

    def status
      if is_running?
        puts "Deploy agent is running. PID #{pid_from_file}"
      else
        puts "Deploy agent is not running."
        Process.exit(1)
      end
    end

    def run
      ensure_configured
      Agent.new(@options).run
    end

    def accesslist
      puts "Access list:"
      DeployAgent.allowed_destinations.each do |destination|
        begin
          IPAddr.new(destination)
          puts " - " + destination
        rescue IPAddr::InvalidAddressError
          puts " - " + destination + " (INVALID)"
        end
      end
      puts
      puts "To edit the list of allowed servers, please modify " + ACCESS_PATH
    end

    def version
      puts DeployAgent::VERSION
    end

    private

    def ensure_configured
      unless File.file?(CERTIFICATE_PATH) && File.file?(ACCESS_PATH)
        puts 'Deploy agent is not configured. Please run "deploy-agent setup" first.'
        Process.exit(1)
      end
    end

    def is_running?
      if pid = pid_from_file
        Process.kill(0, pid)
        true
      else
        false
      end
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def pid_from_file
      File.read(PID_PATH).to_i
    rescue Errno::ENOENT
      nil
    end

    def write_pid
      File.open(PID_PATH, 'w') { |f| f.write Process.pid.to_s }
      at_exit { File.delete(PID_PATH) if File.exist?(PID_PATH) }
    end

  end
end
