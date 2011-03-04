spec = Gem::Specification.new do |s|
  s.name = 'smith'
  s.version = '0.7.1'
  s.date = '2010-08-08'
  s.summary = 'Multi-agent framework'
  s.email = "rgh@filterfish.org"
  s.homepage = "http://github.com/filterfish/smith/"
  s.description = "Simple multi-agent framework"
  s.has_rdoc = false
  s.rubyforge_project = "nowarning"

  s.authors = ["Richard Heycock"]
  s.add_dependency "eventmachine", ">= 0.12.10"
  s.add_dependency "logging"
  s.add_dependency "daemons", ">= 1.1.0"
  s.add_dependency "trollop"
  s.add_dependency "extlib"
  s.add_dependency "bunny"
  s.add_dependency "amqp", ">= 0.6.7"

  binaries = %w{agency send smithctl pop-queue remove-queue}
  libraries = Dir.glob("lib/**/*")

  s.executables = binaries

  s.files = binaries.map { |b| "bin/#{b}" } + libraries
  s.files << 'doc/Changelog'
end
