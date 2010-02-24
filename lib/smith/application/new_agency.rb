#!/usr/bin/env ruby

$:.unshift(File.dirname(__FILE__))

require 'rubygems'
require 'pathname'
require 'logging'
require 'trollop'
require 'extlib'
require 'pp'
require 'mq'

class Agency
  def initialize(base_path)
    @base_path = base_path
    @agents_managed = []

    @bootstraper = File.join($:.first, '..', 'bootstrap.rb')

    rails_env = (ENV['RAILS_ENV'].nil?) ? 'development' : ENV['RAILS_ENV']
    #Logging.configure(AppConfig.app_root + "/config/logging/#{rails_env}.yml")
    Logging.configure("./config/logging.yml")
    @logger = Logging::Logger['audit']
  end

  def setup_signal_handlers
    %w{INT TERM QUIT}.each do |sig|
      trap sig, lambda { AMQP.stop { EM.stop; puts "Shutting down"; exit } }
    end
  end

  def setup_queue_handlers
    # Set up queue to manage new agents
    RubyMAS::Messaging.new(:manage, :durable => false).receive_message do |header, agent|
      begin
        start_agent(agent)
        @agents_managed << agent unless @agents_managed.include?(agent)
      rescue RuntimeError => e
        @logger.error(e)
        @logger.error("Cannot load agent: #{agent}")
      end
    end

    RubyMAS::Messaging.new(:agents_shutdown, :durable => false).receive_message do |header, message|
      if message == 'all'
        agents_to_terminate = @agents_managed
      else
        if @agents_managed.include?(message)
          agents_to_terminate = [message]
        else
          agents_to_terminate = []
          @logger.error("Cannot kill agent #{message}, it doesn't exist.")
        end
      end

      agents_to_terminate.each do |agent|
        if PIDFileUtilities.process_exists?(agent)
          # Make sure the restart agent is not monitoring the agent.
          RubyMAS::Messaging.new(:unmonitor, :durable => false).send_message(agent)
          @logger.info("Sending kill message to #{agent}")
          RubyMAS::Messaging.new("agent.#{agent.snake_case}", :durable => false).send_message("kill")
        end
      end
    end
  end

  def logger
  end
  private

  def start_agent(agent)
    if PIDFileUtilities.process_exists?(agent)
      @logger.error("Not starting: #{agent}. Agent already exists")
    else
      pid = fork do
        # Detach from the controlling terminal
        unless sess_id = Process.setsid
          raise 'Cannot detach from controlled terminal'
        end

        # Close all file descriptors apart from stdin, stdout, stderr
        ObjectSpace.each_object(IO) do |io|
          unless [STDIN, STDOUT, STDERR].include?(io)
            io.close rescue nil
          end
        end

        # Sort out the remaining file descriptors. Don't do anything with
        # stdout (and by extension stderr) as want the agency to manage it.
        STDIN.reopen("/dev/null")
        STDERR.reopen(STDOUT)

        @logger.info("Starting: #{agent}")
        pp @base_path
        exec('/usr/bin/ruby', @bootstraper, @base_path, agent)
      end
      # We don't want any zombies.
      Process.detach(pid)
    end
  end
end
