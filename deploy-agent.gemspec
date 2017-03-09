Gem::Specification.new do |s|
  s.name        = 'deploy-agent'
  s.version     = '1.0.1'
  s.summary     = "The Deploy agent"
  s.description = "This gem allows you to configure a secure proxy through which Deploy can forward connections"
  s.authors     = ["aTech Media"]
  s.email       = ["support@deployhq.com"]
  s.files       = Dir.glob("{lib,bin}/**/*")
  s.homepage    = 'https://www.deployhq.com/'
  s.bindir      = "bin"
  s.executables << 'deploy-agent'
  s.add_runtime_dependency 'nio4r', '1.2.1'
  s.add_runtime_dependency 'rb-readline', '0.5.4'
end
