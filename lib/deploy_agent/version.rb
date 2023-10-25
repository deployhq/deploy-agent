require "rubygems"

module DeployAgent
  VERSION_FILE_PATH = File.expand_path('../../../VERSION', __FILE__)
  SPEC_FILE_PATH    = File.expand_path('../../../deploy-agent.gemspec', __FILE__)

  if File.file?(VERSION_FILE_PATH)
    VERSION = File.read(VERSION_FILE_PATH).strip.sub(/\Av/, '')
  elsif File.file?(SPEC_FILE_PATH)
    VERSION = Gem::Specification::load(SPEC_FILE_PATH).version.to_s
  else
    puts __FILE__

    VERSION = '0.0.0.dev'
  end

end
