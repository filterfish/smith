$:.unshift(File.dirname(__FILE__))

require 'mq'
require 'em/iterator'
require 'smith/agent'
require 'smith/messaging'
require 'daemons/pidfile_mp'
