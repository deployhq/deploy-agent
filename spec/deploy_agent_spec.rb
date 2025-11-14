# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeployAgent do
  describe 'module constants' do
    it 'defines CONFIG_PATH' do
      expect(DeployAgent::CONFIG_PATH).to eq(File.expand_path('~/.deploy'))
    end

    it 'defines CERTIFICATE_PATH' do
      expect(DeployAgent::CERTIFICATE_PATH).to eq(File.expand_path('~/.deploy/agent.crt'))
    end

    it 'defines KEY_PATH' do
      expect(DeployAgent::KEY_PATH).to eq(File.expand_path('~/.deploy/agent.key'))
    end

    it 'defines PID_PATH' do
      expect(DeployAgent::PID_PATH).to eq(File.expand_path('~/.deploy/agent.pid'))
    end

    it 'defines LOG_PATH' do
      expect(DeployAgent::LOG_PATH).to eq(File.expand_path('~/.deploy/agent.log'))
    end

    it 'defines ACCESS_PATH' do
      expect(DeployAgent::ACCESS_PATH).to eq(File.expand_path('~/.deploy/agent.access'))
    end
  end

  describe '.allowed_destinations' do
    let(:temp_access_file) { "/tmp/test_access_#{Process.pid}" }

    before do
      stub_const('DeployAgent::ACCESS_PATH', temp_access_file)
    end

    after do
      FileUtils.rm_f(temp_access_file)
    end

    it 'reads destinations from access file' do
      File.write(temp_access_file, "127.0.0.1\n192.168.1.0/24\n")
      expect(DeployAgent.allowed_destinations).to eq(['127.0.0.1', '192.168.1.0/24'])
    end

    it 'strips whitespace from destinations' do
      File.write(temp_access_file, "  127.0.0.1  \n  192.168.1.1  \n")
      expect(DeployAgent.allowed_destinations).to eq(['127.0.0.1', '192.168.1.1'])
    end

    it 'ignores empty lines' do
      File.write(temp_access_file, "127.0.0.1\n\n192.168.1.1\n")
      expect(DeployAgent.allowed_destinations).to eq(['127.0.0.1', '192.168.1.1'])
    end

    it 'ignores comment lines' do
      File.write(temp_access_file, "# Comment\n127.0.0.1\n# Another comment\n192.168.1.1\n")
      expect(DeployAgent.allowed_destinations).to eq(['127.0.0.1', '192.168.1.1'])
    end

    it 'extracts only the first field from each line' do
      File.write(temp_access_file, "127.0.0.1 localhost\n192.168.1.1 description\n")
      expect(DeployAgent.allowed_destinations).to eq(['127.0.0.1', '192.168.1.1'])
    end
  end
end
