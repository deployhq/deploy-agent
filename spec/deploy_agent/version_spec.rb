# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeployAgent::VERSION do
  it 'is defined' do
    expect(DeployAgent::VERSION).not_to be_nil
  end

  it 'has a valid semantic version format' do
    expect(DeployAgent::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
