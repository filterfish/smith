task :gem do
  sh 'git log > doc/Changelog'
  sh 'gem build *.gemspec'
  sh 'rm doc/Changelog'
end
