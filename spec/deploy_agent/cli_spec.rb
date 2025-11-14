# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeployAgent::CLI do
  let(:cli) { described_class.new }

  describe '#dispatch' do
    it 'responds to version command' do
      expect { cli.dispatch(['version']) }.to output(/\d+\.\d+\.\d+/).to_stdout
    end

    it 'shows usage for invalid command' do
      expect { cli.dispatch(['invalid']) }.to output(/Usage: deploy-agent/).to_stdout
    end

    it 'shows usage when no arguments provided' do
      expect { cli.dispatch([]) }.to output(/Usage: deploy-agent/).to_stdout
    end
  end

  describe '#version' do
    it 'outputs the version number' do
      expect { cli.version }.to output("#{DeployAgent::VERSION}\n").to_stdout
    end
  end
end
