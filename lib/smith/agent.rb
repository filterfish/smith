require 'pp'
require 'mq'
require 'logging'
require 'extlib'

module RubyMAS
  class Agent
    def initialize(options={})

      raise ArgumentError, "You must specify at least one queue" unless defined?(@@agent_queues)

      @queues = {}
      @signals = (options[:signals]) ? [options[:signals]].flatten : %w{TERM INT QUIT}
      @logger = options[:logger] || Logging.logger(STDOUT)
      @pid_file = PIDFileUtilities.new(Process.pid, self.class.name)

      @signal_handlers = []
      @agent_name = self.class.to_s.snake_case

      $0 = "#{@agent_name}"

      signal_handler = install_signal_handler do
        @logger.debug("Running #{@agent_name}'s default signal handler")
        send_terminate_message
        @pid_file.remove
      end

      add_queues(@@agent_queues)

      if options[:restart]
        @logger.debug("Sending agent name [#{self.class.to_s}] to restart agent")
        Messaging.new(:monitor, :durable => false).send_message(self.class.to_s)
      end

      @logger.debug "Setting up termination handler"
      setup_message_handlers
    end

    # Install any signal handlers. This can be called muliple times
    # in which case each handler is added to the front of a queue of
    # handlers and execute in that order.
    def install_signal_handler(&handler)
      # Insert any new handlers at the front of the array.
      @signal_handlers.insert(0, handler)

      signal_handler = lambda {
        run_signal_handlers
      }

      @signals.each do |signal|
        trap signal, signal_handler
      end
    end

    # Specify a queue that the agent can use. All queues must be specified up
    # front otherwise an ArgumentError will be thrown.
    def add_queue(queue_name, options={})
      @queues[queue_name.to_sym] = Messaging.new(queue_name, options) unless @queues.include?(queue_name.to_sym)
    end

    # Send a message to the named queue. The message is marshalled.
    def send_message(queue, message="", options={})
      if @queues[queue.to_sym]
        @queues[queue.to_sym].send_message(message, options)
      else
        raise RuntimeError, "No such Queue: #{queue} for #{@agent_name}"
      end
    end

    def send_and_receive(queue, message="", options={})
      if @queues[queue.to_sym]
        @queues[queue.to_sym].send_and_receive(message, options) do |header,message,pass_through|
          yield header,message,pass_through
        end
      else
        raise RuntimeError, "No such Queue: #{queue} for #{@agent_name}"
      end
    end

    # Reply to a message. This will only work if the reply_to header is set.
    def reply_to(header, message, options={})
      if header.reply_to
        begin
          # This may be a problem if a message is already declared :auto_delete => false
          queue = Messaging.new(header.reply_to, :auto_delete => true)
          queue.send_message(message, {:message_id => header.message_id, :pass_through => @pass_through}.merge(options))
          queue.close
        rescue => e
          @logger.error(e)
        end
      end
    end

    # Receive a message synchronously. If the agent throws an exception
    # it will stop AMQP & eventmachine meaning the overall process
    # will die. However no messages will be lost as they won't have been
    # ack'ed; when the process next starts the message will be redelivered.
    def get_message(queue, options={}, &block)
      if @queues[queue.to_sym]
        @queues[queue.to_sym].receive_message(options) do |header,message,pass_through|
          begin
            if AMQP.closing?
              @logger.error("Message ignored; it will be redelivered later")
            else
              @pass_through = pass_through
              block.call(header, message, @pass_through)
            end
          rescue Exception => e
            @logger.error("Error in agent #{@agent_name}: #{e}")
            @logger.error(e)
            @logger.error("Stopping EM")
            @pid_file.remove
            AMQP.stop { EM.stop }
#          ensure
#            run_signal_handlers
          end
        end
      else
        raise RuntimeError, "No such Queue: #{queue} for #{@agent_name}"
      end
    end

    protected

    def logger
      @logger
    end

    class << self
      # Specify any queues that the agent will use. There must
      # be at least one queue specified. This can be called multiple times.
      # If the last argument is a hash it will be used as queue options.
      def queues(*queues)
        opts = (queues.last.is_a?(Hash)) ? queues.delete(queues.last) : {}
        queues.each { |queue| queue(queue, opts) }
      end

      # Specify a single queue that the agent will use. Whilst you can
      # specify a single queue using Agent.queues you cannot specify
      # any options. Only use this method if you need to specify any
      # options.
      def queue(queue, opts={})
        @@agent_queues = [] unless defined?(@@agent_queues)
        @@agent_queues << [queue,opts]
      end
    end

    private

    def run_signal_handlers
      @logger.info("#{self.class.to_s} shutting down. Running signal handlers")
      send_terminate_message
      @signal_handlers.each { |handler| handler.call }
      EM.next_tick { AMQP.stop { EM.stop; } }
    end

    # Convenience method to create multiple queues.
    def add_queues(queue_names)
      queue_names.each do |queue_name,opts|
        add_queue(queue_name, opts)
      end
    end

    def setup_message_handlers
      queue_name = "agent.#{@agent_name}"
      queue = Messaging.new(queue_name, :durable => false)
      queue.receive_message do |h,payload|
        case payload
        when 'shutdown'
          @logger.info("#{self.class.to_s} received shutdown message. Time to die")
          h.ack
          run_signal_handlers
        else
          @logger.warn("Unhandled message for #{@agent_name}")
        end
      end
    end

    # Send a message saying I'm dying
    def send_terminate_message
      @logger.debug("Sending #{@agent_name}'s terminate message")
      Messaging.new(:terminated, :auto_delete => true).send_message(:agent => @agent_name)
    end
  end
end
