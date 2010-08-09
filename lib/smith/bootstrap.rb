# This should never be run directly it should only be
# ever run by the agency.

require 'daemons/pidfile'
require File.dirname(__FILE__) + '/../smith'

# Monkey patch Daemons::PidFile.pid as it doesn't take a
# filesystem lock and therefore is the source of a race condition.
module Daemons
  class PidFile
    def pid=(p)
      ok = false
      begin
        f = File.new(filename, 'w', 0600)
        if f.flock(File::LOCK_EX || File::LOCK_NB)
          f.puts(p)
          ok = true
        end
      ensure
        f.flock(File::LOCK_UN)
      end
      ok
    end
  end
end

class AgentBootstrap

  def initialize(path, agent_name, logger)
    @logger = logger

    @agent_name = agent_name
    @agent_filename = File.expand_path(File.join(path, "#{agent_name.snake_case}.rb"))
  end

  def load_agent
    load @agent_filename
    @pid.pid = Process.pid
  end

  def run
    begin
      agent_instance = Kernel.const_get(@agent_name).new(:logger => @logger)
      agent_instance.run
    rescue => e
      @logger.error("Failed to run agent: #{@agent_name}: #{e}")
      @logger.error(e)
    end
  end

  def write_pid_file
    @pid = Daemons::PidFile.new(Daemons::Pid.dir(:normal, Dir::tmpdir, nil), ".rubymas-#{@agent_name.snake_case}")
    if @pid.exist?
      if @pid.running?
        false
      else
        @pid.pid = Process.pid
      end
    else
      @pid.pid = Process.pid
    end
  end

  def unlink_pid_file
    @pid.cleanup
  end
end

path = ARGV[0]
agent_name = ARGV[1]
logging_config = ARGV[2]

exit 1 if agent_name.nil? || path.nil? || logging_config.nil?

Logging.configure(logging_config)
logger = Logging::Logger['audit']

# Set the running instance name to the name of the agent.
$0 = "#{agent_name}"

agent = AgentBootstrap.new(path, agent_name, logger)

if agent.write_pid_file
  agent.load_agent

  # Make sure the pid file is removed
  at_exit { agent.unlink_pid_file }

  EM.epoll
  EM.run {
    agent.run
  }
else
  logger.error("Another instance of #{agent_name} is already running")
end
