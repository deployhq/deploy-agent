module DeployAgent
  class CLI
    def run(arguments)
      case arguments[0]
      when 'status'
        status
      when 'start'
        start_server
      when 'stop'
        stop_server
      when 'restart'
        restart_server
      when 'run'
        run_server
      when 'setup'
        CertificateManager.new.generate_certificate
      else
        puts "Usage: deploy-agent [start|stop|restart|status|run|setup]"
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
      at_exit { File.delete(PID_PATH) if File.exists?(PID_PATH) }
    end

    def restart_server
      stop_server
      while(is_running?)
        sleep 0.5
      end
      start_server
    end

    def start_server
      if is_running?
        puts "Deploy agent already running. Process ID #{pid_from_file}"
        Process.exit(1)
      else
        pid = fork do
          $background = true
          write_pid
          run_server
        end
        puts "Deploy agent started. Process ID #{pid}"
        Process.detach(pid)
      end
    end

    def stop_server
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

    def run_server
      Agent.new.run
    end

  end
end
