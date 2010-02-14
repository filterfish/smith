unless defined?(AppConfig)
  require 'app_config'

  rails_env = (ENV['RAILS_ENV'].nil?) ? 'development' : ENV['RAILS_ENV']

  ::AppConfig = ApplicationConfiguration.new(File.dirname(__FILE__) + "/../../config/app_config.yml",
                                             File.dirname(__FILE__) + "/../../config/environments/#{rails_env}.yml")
end
