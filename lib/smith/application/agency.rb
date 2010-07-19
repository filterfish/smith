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
    RubyMAS::Messaging.new(:manage).receive_message do |header, agent|
      begin
        if !agents_available(agent).empty?
          start_agent(agent)
          @agents_managed << agent unless @agents_managed.include?(agent)
        else
          @logger.error("Agent not known: #{agent}")
        end
      rescue RuntimeError => e
        @logger.error(e)
        @logger.error("Cannot load agent: #{agent}")
      end
    end

    RubyMAS::Messaging.new(:agents_shutdown).receive_message do |header, payload|
      if payload == 'all'
        agents_to_terminate = @agents_managed
      else
        if @agents_managed.include?(payload)
          agents_to_terminate = [payload]
        else
          agents_to_terminate = []
          @logger.error("Cannot shutdown agent #{payload}, it doesn't exist.")
        end
      end

      agents_to_terminate.each do |agent|
        if PIDFileUtilities.process_exists?(agent)
          # Make sure the restart agent is not monitoring the agent.
          RubyMAS::Messaging.new(:unmonitor).send_message(agent)
          @logger.info("Sending unmonitor message to #{agent}")
          RubyMAS::Messaging.new("agent.#{agent.snake_case}").send_message("shutdown")
        end
        @agents_managed.delete(agent)
      end
    end

    RubyMAS::Messaging.new(:agents_list).receive_message do |header, payload|
      if header.reply_to
        @logger.debug("Agents managed: #{@agents_managed}")
        queue = RubyMAS::Messaging.new(header.reply_to, :auto_delete => true)
        queue.send_message(@agents_managed, :message_id => header.message_id)
      end
    end

    RubyMAS::Messaging.new(:agents_available).receive_message do |header, payload|
      if header.reply_to
        queue = RubyMAS::Messaging.new(header.reply_to, :auto_delete => true)
        agents = (payload && payload[:agent]) ? agents_available(payload[:agent]) : agents_available
        queue.send_message(agents, :message_id => header.message_id)
      end
    end

    RubyMAS::Messaging.new(:terminated).receive_message do |header, payload|
      @agents_managed.delete(payload[:agent].camel_case)
    end
  end

  private

  def agents_available(agent=nil)
    glob = (agent) ? "#{agent.snake_case}.rb" : '*.rb'
    Dir.glob(File.join(@base_path, glob)).map { |a| File.basename(a, '.rb').camel_case }
  end

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
        exec('ruby', @bootstraper, @base_path, agent)
      end
      # We don't want any zombies.
      Process.detach(pid)
    end
  end
end
