# kafka-simple-chat

A simple messaging application written in ruby. Uses Apache Kafka as its 'backend'.

## Requirements
1. Ruby 2.2+
2. Apache Kafka 0.8.2+

## Setup
This tutorial assumes that your Kafka server has been started.
1. Execute `gem install bundler`
2. In the project folder, execute `bundler install` to install the project dependencies

## Run
Run the client by typing `ruby lib/client.rb`.  
You can optionally pass arguments when running the client. These will be interpreted,
sequentially, as follows:
* host
* port
* nick

For example, running `ruby lib/client.rb localhost 8000` will connect the client to the Kafka
server running at localhost, on port 8000, with a randomly generated nickname.

## Commands
Aside from the standard commands (`/nick`, `/join`, `/leave`, and `@`), we also
implemented the following commands:

### `/show`
Shows the messages stored in the buffer. Prints `No new messages` if no message is available.

## TODO
* Detecting duplicate nicknames
