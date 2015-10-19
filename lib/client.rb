require "rubygems"
require "bundler/setup"

require "poseidon"
require "digest/sha3"

class Client
  attr_reader :channels
  attr_reader :nick

  def initialize(options = {})
    @host = options[:host] || "localhost"
    @port = options[:port] || 9092
    @nick = options[:nick] || ('a'..'z').to_a.shuffle[0, 8].join
    @id = self.generate_id
    @channels = {}

    @producer = Poseidon::Producer.new(["#{@host}:#{@port}", @id])
  end

  private
  def generate_id(new_nick = '')
    nick = new_nick.nil? || new_nick.empty? ? @nick : new_nick
    Digest::SHA3.hexdigest("#{@host}#{@port}#{nick}")
  end

  def process_command(input)
    # tokenize input, split by whitespace
    tokens = input.gsub(/\s+/m, ' ').strip.split(' ')
    raise ArgumentError, 'No input supplied!' unless tokens.any?

    # get substring after first char
    command = tokens.first

    # process the commands
    if command.start_with?('/')
      case command[1..-1]
      when 'nick'
        command_nick(tokens[1..-1].join(' '))
      when 'join'
        command_join(tokens[1..-1].join(' '))
      when 'leave'
        command_leave(tokens[1..-1].join(' '))
      else
        raise ArgumentError, "Unknown command #{command}."
      end
    elsif command.start_with?('@')
      channel = command[1..-1]
      command_say(tokens[1..-1].join(' '), channel)
    else
      command_say(tokens.join(' '))
    end
  end

  private
  def command_say(message, channel = '')
    if channel.nil? || channel.empty?
      raise "You currently do not join channel #{channel}." unless @channels.include?(channel)

      @producer.send_messages([Poseidon::MessageToSend.new(channel, message)])
    else
      raise "You are currently not joined on any channel." unless @channels.any?

      messages = []
      @channels.keys.each { |ch|
        messages.push(Poseidon::MessageToSend.new(ch, message))
      }
      @producer.send_messages(messages)
    end
  end

  # updates the nickname of this Client
  # will fail if
  # - cannot connect to the producer using the new client id
  # - cannot connect to any of the currently connected channels using the new client id
  private
  def command_nick(new_nick)
    old_id = @id
    updated_channels = []

    begin
      @producer.close()

      @id = self.generate_id(new_nick)
      @producer = Poseidon::Producer.new(["#{@host}:#{@port}", @id])

      @channels.each { |key, ch|
        ch.close
        @channels[key] = Poseidon::PartitionConsumer.new("consumer_#{@id}", @host, @port, key, 0, :earliest_offset)
        updated_channels.push(key)
      }

      @nick = new_nick.to_s
      puts "Changed nick to #{@nick}"
    rescue Exception => e
      puts "Cannot change nick to #{new_nick}: #{e.message}"
      @id = old_id

      # currently, if any of the following connection fails, the whole program will crash.
      @producer = Poseidon::Producer.new(["#{@host}:#{@port}", @id])
      updated_channels.each { |ch|
        @channels[ch].close
        @channels[ch] = Poseidon::PartitionConsumer.new("consumer_#{@id}", @host, @port, key, 0, :earliest_offset)
      }
    end
  end

  private
  def command_join(channel)
    raise "You already joined #{channel}!" unless !@channels.has_key?(channel)

    begin
      ch = channel.to_s

      @channels[ch] = Poseidon::PartitionConsumer.new("consumer_#{@id}", @host, @port, ch, 0, :earliest_offset)
      puts "Joined channel #{channel}."
    rescue Exception => e
      puts "Cannot connect to #{channel}: #{e.message}"
    end
  end

  private
  def command_leave(channel)
    raise "You are not joined with channel #{channel}!" unless @channels.has_key?(channel.to_s)

    begin
      ch = channel.to_s
      @channels[ch].close
      @channels.tap { |hs| hs.delete(ch) }

      puts "Left channel #{channel}."
    rescue Exception => e
      puts "Cannot leave channel #{channel}: #{e.message}"
    end
  end
end
