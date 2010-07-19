spec = Gem::Specification.new do |s|
  s.name = 'smith'
  s.version = '0.5'
  s.date = '2010-07-19'
  s.summary = 'Multi-agent framework'
  s.email = "rgh@filterfish.org"
  s.homepage = "http://github.com/filterfish/smith/"
  s.description = "Simple multi-agent framework"
  s.has_rdoc = false
  s.rubyforge_project = "nowarning"

  s.authors = ["Richard Heycock"]
  s.add_dependency "eventmachine"
  s.add_dependency "logging"
  s.add_dependency "trollop"
  s.add_dependency "extlib"
  s.add_dependency "bunny"
  s.add_dependency "bert"
  s.add_dependency "amqp"

  binaries = %w{agency send smithctl}
  libraries = Dir.glob("lib/**/*")

  s.executables = binaries

  s.files = binaries.map { |b| "bin/#{b}" } + libraries
  s.files << 'doc/Changelog'
end
