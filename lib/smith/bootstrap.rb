# This should never be run directly it should only be
# ever run by the agency.

$root = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))

$:.unshift(File.join($root, "lib"))

require 'smith'

class AgentBootstrap

  def initialize(path, agent)
    setup_logger
    @agent = agent
    @agent_filename = File.join(path, "#{agent.snake_case}.rb")
  end

  def load_agent
    load @agent_filename
  end

  def run
    begin
      agent_instance = Kernel.const_get(@agent).new(:logger => @logger)
      agent_instance.run
    rescue => e
      @logger.error("Failed to run agent: #{@agent}: #{e}")
    end
  end

  private

  def setup_logger
    rails_env = (ENV['RAILS_ENV'].nil?) ? 'development' : ENV['RAILS_ENV']
    Logging.configure("config/logging.yml")
    @logger = Logging::Logger['audit']
  end
end

path = ARGV[0]
agent_name = ARGV[1]
exit 1 if agent_name.nil? || path.nil?

EM.epoll
EM.run {
  bootstraper = AgentBootstrap.new(path, agent_name)
  bootstraper.load_agent
  bootstraper.run
}
