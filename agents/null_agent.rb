class NullAgent < RubyMAS::Agent

  queues :test

  def initialize(opts={})
    super(opts.merge(:restart => true))
  end

  def run
    get_message(:test) do |header,message|
      puts "#{Time.now}, #{message}"
    end
  end
end
