Smith
=====

Note. This README is very much a work in progress. Expect more soon.

Simple multi-agent framework based on Eventmachine and AMQP.

Installation
------------

rake build

gem install smith-<version>.gem


You will also need a reasonably recent version of [rabbitmq](http://www.rabbitmq.com/ "rabbitmq"). (it needs to support prefetch).

Usage
-----

You will need to run the agency on a machine specifying the logging configuration and the directory containing the agents.

For example:

  agency -a ./agents -l config/logging.yml


The logging gem is used for logging so see the doco for that for more details. You can use the supplied log file to get you going.

To see all the options run

  agency --help


There is a utility called smithctl which allows you to issue commands to the agency. The following commands are supported:

- agents - show the available agents
- list (ls is an alias) list the running agents
- message - send a message to a queue
- restart - restart an agent
- start - start an agent
- stop - stop an agent

I will point out that smithctl is not *that* reliable when is comes to listing agents (See known issues). The other commands all work as expected.

You can also pass commands to smithctl on the command line:

  smithctl agents


Known Issues
------------

- Running multiple agencies on different machines is not yet supported, though it should be reasonably straightforward to implement it.
- The agency really needs a config system.
- There are issues with the agency keeping track of agents (this doesn't matter in terms of the individual agents but it can be nuisance)

Other stuff
-----

To use smith you really should get to grips with [eventmachine](http://rubyeventmachine.com/ "eventmachine") & in particular it's no blocking nature. AMQP has mainly been abstracted away but it would probably be worth your while to read up on it: [amqp gem](http://github.com/tmm1/amqp "amqp") and [rabbitmq](http://www.rabbitmq.com/ "rabbitmq").

Oh and patches are more than welcome!
