require 'mq'
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
      options = {:durable => false}.merge(options)

      @exchange = MQ::Exchange.new(@mq, :direct, queue_name.to_s, options)
      @queue = MQ::Queue.new(@mq, queue_name.to_s, options).bind(@exchange)
    end

    def send_message(message, options={})
      @exchange.publish(encode({:message => message, :pass_through => options.delete(:pass_through)}), {:ack => true}.merge(options))
    end

    def receive_message(options={}, &block)
      receive_message_from_queue(@queue, options, &block)
    end

    def send_and_receive(message, options={}, &block)
      timeout = options.delete(:timeout) || 300
      on = options.delete(:on)

      if on
        case
        when @on_return_quene_name
          reply_queue_name = @on_return_quene_name
          receive_queue = @receive_queue
        when on.to_sym == :internal
          @on_return_quene_name = random("reply.")
          @receive_queue = MQ::Queue.new(@mq, @on_return_quene_name, options)
        else
          @on_return_quene_name = on.to_s
          @receive_queue = MQ::Queue.new(@mq, @on_return_quene_name, options)
        end
        reply_queue_name = @on_return_quene_name
        receive_queue = @receive_queue
      else
        reply_queue_name = random("reply.")
        receive_queue = MQ::Queue.new(@mq, reply_queue_name, options)
      end

      send_message(message, options.merge(:reply_to => reply_queue_name, :message_id => random))

      receive_message_from_queue(receive_queue, {:once => false}.merge(options)) do |header,message,pass_through|
        yield header, message, pass_through
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

    def receive_message_from_queue(queue, options={}, &block)
      options = {:ack => true, :auto_ack => true}.merge(options)
      once = options.delete(:once)
      if !queue.subscribed?
        queue.subscribe(options) do |header,message|
          decoded_message = decode(message)
          if decoded_message
            block.call header, decoded_message[:message], decoded_message[:pass_through]
            queue.unsubscribe if once
            header.ack if options[:ack] && options[:auto_ack]
          end
        end
      end
    end

    def random(prefix = '', suffix = '')
      "#{prefix}#{rand(999_999_999).to_s(16)}#{suffix}"
    end
  end

  module Sync
    require 'bunny'

    class Messaging

      include Encoding

      def initialize(queue_name, options={})
        @bunny = Bunny.new(options)

        @options = {:durable => false}.merge(options)
        @queue_name = queue_name
      end

      def send_message(message, options={})
        bunny_run do |bunny|
          queue = bunny.queue(@queue_name, @options.merge(:durable => @options[:durable]))
          queue.publish(encode({:message => message, :pass_through => options.delete(:pass_through)}), options)
        end
      end

      # Send and a message to the named queue and wait for the response. The return
      # queue is automatically generated.
      def send_and_receive_message(message, options={})
        block_return = nil

        timeout = options.delete(:timeout) || 300

        bunny_run do |bunny|
          response = nil
          message_id = rand(999_999_999_999).to_s(16)
          reply_queue_name = "reply." + rand(999_999_999).to_s(16)

          send_queue = bunny.queue(@queue_name, @options)
          message = {:message => message, :pass_through => options.delete(:pass_through)}
          send_queue.publish(encode(message), :reply_to => reply_queue_name, :ack => true, :message_id => message_id)

          reply_queue = bunny.queue(reply_queue_name, :durable => false, :auto_delete => true)
          reply_queue.subscribe(:header => true, :message_max => 1, :timeout => timeout, :ack => true) do |return_message|
            if return_message[:header].message_id == message_id
              response = decode(return_message[:payload])
              if block_given?
                block_return = yield return_message[:header], response[:message], response[:pass_through]
              else
                block_return = [response[:message], response[:pass_through]]
              end
            else
              puts("Discarding message as the message_id does not match")
            end
          end

          if response.nil?
            raise Timeout, "No message received within #{timeout} seconds"
          end
        end
        return block_return
      end

      private

      # Use instead of Bunny.run to avoid the cost of creating a client every message.
      def bunny_run
        @bunny.start
        yield @bunny
        @bunny.stop
      end
    end
  end
end
