require 'pp'
require 'mq'
require 'yajl'
require 'logging'
require 'extlib'

module RubyMAS

  class Timeout < RuntimeError; end

  module Encoding
    def encode(message)
      Marshal.dump(message)
    end

    def decode(message)
      Marshal.load(message)
    end
  end

  class Messaging

    include Encoding

    # Create a messaging object. Options must be one of the following:
    # :durable
    # :auto_delete
    # :exclusive
    def initialize(queue_name, options={})
      @mq = MQ.new

      # Set up QOS. If you do not do this then the subscribe in receive_message
      # will get overwelmd and the whole thing will collapse in on itself.
      @mq.prefetch(1)

      @exchange = MQ::Exchange.new(@mq, :direct, queue_name.to_s, options)
      @queue = MQ::Queue.new(@mq, queue_name.to_s, options).bind(@exchange)
    end

    def send_message(message, options={})
      @exchange.publish(encode(message), {:ack => true}.merge(options))
    end

    def receive_message(options={})
      options = {:ack => true}.merge(options)
      @queue.subscribe(options) do |header,message|
        if message
          yield header, decode(message)
          header.ack if options[:ack]
        end
      end
    end

    def number_of_messages
      @queue.status do |num_messages, num_consumers|
        yield num_messages
      end
    end

    def close
      @mq.close
    end
  end

  module Sync
    require 'bunny'

    class Messaging

      include Encoding

      def initialize(queue_name, options={})
        @bunny = Bunny.new(options)

        @options = {:durable => true}.merge(options)
        @queue_name = queue_name
      end

      def send_message(message, options={})
        bunny_run do |bunny|
          queue = bunny.queue(@queue_name, @options.merge(:durable => @options[:durable]))
          queue.publish(encode(message), options)
        end
      end

      def receive_message(options={})
        bunny_run do |bunny|
          queue = bunny.queue(@queue_name, @queue_options.merge(:durable => @options[:durable]))
          queue.pop(options.merge(:ack => true))
        end
      end

      def send_and_receive_message(message, opts={})
        response = nil

        timeout = opts.delete(:timeout) || 300

        bunny_run do |bunny|
          message_id = rand(999_999_999_999).to_s(16)
          reply_queue_name = "reply." + rand(999_999_999).to_s(16)

          send_queue = bunny.queue(@queue_name, @options.merge(:auto_delete => true))
          send_queue.publish(encode(message), :reply_to => reply_queue_name, :ack => true, :message_id => message_id)

          reply_queue = bunny.queue(reply_queue_name, :exclusive => true, :durable => false)
          reply_queue.subscribe(:header => true, :message_max => 1, :timeout => timeout, :ack => true) do |return_message|
            if return_message[:header].message_id == message_id
              response = decode(return_message[:payload])
            else
              puts("Discarding message as the message_id does not match")
            end
          end
          if response.nil?
            raise Timeout, "No message received within #{timeout} seconds"
          end
        end
        response
      end

      private

      # Use instead of Bunny.run to avoid the cost of create a client
      # every message.
      def bunny_run
        @bunny.start
        yield @bunny
        @bunny.stop
      end
    end
  end
end
