spec = Gem::Specification.new do |s|
  s.name = 'smith'
  s.version = '0.3'
  s.date = '2010-05-18'
  s.summary = 'Multi-agent framework'
  s.email = "rgh@topikality.com"
  s.homepage = "http://github.com/filterfish/smith/"
  s.description = "Simple multi-agent framework"
  s.has_rdoc = false

  s.authors = ["Richard Heycock"]
  s.add_dependency "eventmachine"
  s.add_dependency "logging"
  s.add_dependency "trollop"
  s.add_dependency "extlib"
  s.add_dependency "bunny"
  s.add_dependency "bert"
  s.add_dependency "amqp"

  s.executables = Dir::glob("bin/*").map{|exe| File::basename exe}

  s.files = Dir.glob("{bin/*,lib/**/*}")
end
