#!/usr/bin/env ruby

$:.unshift(File.dirname(__FILE__))

require 'pathname'
require 'logging'
require 'extlib'
require 'mq'

class Agency
  def initialize(opts={})
    @base_paths = opts[:agents_dir] or raise ArgumentError, "no agents path supplied"

    @logging_path = opts[:logging]
    @logger = opts[:logger]

    if @logging_path.nil? && @logger.nil?
      @logging_path = opts[:logging] or raise ArgumentError, "agency has no logging path supplied or logger"
    end

    @agents_managed = []

    @bootstraper = File.join($:.first, '..', 'bootstrap.rb')

    unless @logger
      Logging.configure(@logging_path)
      @logger = Logging::Logger['audit']
    end
  end

  def write_pid_file
    @pid = Daemons::PidFile.new(Daemons::Pid.dir(:normal, Dir::tmpdir, nil), ".rubymas-agency")
    if @pid.exist?
      if @pid.running?
        @logger.warn("Agency is already running")
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

  def setup_signal_handlers
    %w{INT TERM QUIT}.each do |sig|
      trap sig, lambda { AMQP.stop { EM.stop; puts "Shutting down"; exit } }
    end
  end

  def setup_queue_handlers
    # Set up queue to manage new agents
    Smith::Messaging.new(:manage).receive_message do |header, agent|
      begin
        unless agents_available(agent).empty?
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

    Smith::Messaging.new(:agents_shutdown).receive_message do |header, payload|
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
        queue = Smith::Messaging.new("agent.#{agent.snake_case}")
        queue.number_of_consumers { |n|
          # Check to see if there is an agent listening.
          if n > 0
            # Make sure the restart agent is not monitoring the agent.
            unmonitor_queue = Smith::Messaging.new(:unmonitor)
            unmonitor_queue.number_of_consumers { |n|
              if n > 0
                unmonitor_queue.send_message(agent)
                @logger.debug("Sending #{agent} to unmonitor queue")
              else
                @logger.debug("Not sending #{agent} to unmonitor queue. Restart agent not listening")
              end
            }
            queue.send_message("shutdown")
            @agents_managed.delete(agent)
          else
            @logger.debug("Not sending unmonitor message to #{agent} as it doesn't exist or is not listening")
          end
        }
      end
    end

    Smith::Messaging.new(:agents_list).receive_message do |header, payload|
      if header.reply_to
        @logger.debug("Agents managed: #{@agents_managed}")
        queue = Smith::Messaging.new(header.reply_to, :auto_delete => true)
        queue.send_message(@agents_managed, :message_id => header.message_id)
      end
    end

    Smith::Messaging.new(:agents_available).receive_message do |header, payload|
      if header.reply_to
        queue = Smith::Messaging.new(header.reply_to, :auto_delete => true)
        agents = (payload && payload[:agent]) ? agents_available(payload[:agent]) : agents_available
        queue.send_message(agents, :message_id => header.message_id)
      end
    end

    Smith::Messaging.new(:terminated).receive_message do |header, payload|
      @agents_managed.delete(payload[:agent].camel_case)
    end
  end

  private

  def agents_available(agent=nil)
    glob = (agent) ? "#{agent.snake_case}.rb" : '*.rb'
    @base_paths.map do |base_path|
      Dir.glob(File.join(base_path, glob)).map { |a| File.basename(a, '.rb').camel_case }
    end.flatten.uniq
  end

  def start_agent(agent)
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
      exec('ruby', @bootstraper, agent_path(agent), agent, @logging_path)
    end
    # We don't want any zombies.
    Process.detach(pid)
  end

  # Get agent path for a specific agent from the array of paths.
  def agent_path(agent)
    @base_paths.detect { |a| Pathname.new(a).join("#{agent.snake_case}.rb").exist? }
  end
end
