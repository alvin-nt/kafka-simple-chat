require "rubygems"
require "bundler/setup"

require "poseidon"

class ChannelError < StandardError; end;

class Client
  attr_reader :channels
  attr_reader :nick

  attr_accessor :host
  attr_accessor :port

  def initialize(options = {})
    @host = options[:host] || "localhost"
    @port = options[:port] > 0 && options[:port] < 65536 ? options[:port] : 9092
    @nick = options[:nick] || ('a'..'z').to_a.shuffle[0, 8].join
    @id = generate_id
    @channels = {}
    @buffer = []

    @mutex = Mutex.new

    @producer = Poseidon::Producer.new(["#{@host}:#{@port}"], @id)
  end

  def fetch_messages
    raise ChannelError.new("You are not joined with any channel!") unless @channels.any?

    @mutex.synchronize do
      @channels.each do |key, ch|
        begin
          messages = ch.fetch({
            :max_wait_ms => 1000
            })
          messages.each do |m|
            @buffer << "[#{key}]#{m.value}"
          end
        rescue
          next
        end
      end
    end
  end

  def print_messages
    if @buffer.empty?
      puts 'No new messages.'
    else
      until @buffer.empty?
        message, qty = @buffer.pop
        puts message
      end
    end
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
      when 'show'
        command_show
      when 'exit'
        command_exit
      else
        raise ArgumentError, "Unknown command #{command[1..-1]}."
      end
    elsif command.start_with?('@')
      channel = command[1..-1]
      command_say(tokens[1..-1].join(' '), channel)
    else
      command_say(tokens.join(' '))
    end
  end

  def has_messages?
    return @buffer.any?
  end

  private
  def generate_id
    seed = ('a'..'z').to_a.shuffle[0, 8].join
    return Digest::SHA256.hexdigest("#{@host}#{@port}#{seed}")
  end

  private
  def command_say(message, channel = '')
    if channel.nil? || channel.empty?
      raise ChannelError.new("You are currently not joined on any channel.") unless @channels.any?

      messages = []
      @channels.keys.each do |ch|
        messages << Poseidon::MessageToSend.new(ch, "(#{@nick}) #{message}")
      end
      @producer.send_messages(messages)
    else
      raise "You currently do not join channel #{channel}." unless @channels.has_key?(channel)
      @producer.send_messages([Poseidon::MessageToSend.new(channel, "(#{@nick}) #{message}")])
    end
  end

  # updates the nickname of this Client
  private
  def command_nick(new_nick)
    @nick = new_nick
  end

  private
  def command_join(channel)
    raise ChannelError.new("You already joined #{channel}!") unless !@channels.has_key?(channel)

    begin
      ch = channel.to_s

      @mutex.synchronize do
        @channels[ch] = Poseidon::PartitionConsumer.new("#{ch}_#{@id}", @host, @port, ch, 0, :latest_offset)
      end

      puts "Joined channel #{channel}."
    rescue Exception => e
      raise ChannelError.new("Cannot connect to #{channel}: #{e.message}")
    end
  end

  private
  def command_leave(channel)
    raise ChannelError.new("You are not joined with channel #{channel}!") unless @channels.has_key?(channel.to_s)

    ch = channel.to_s
    @mutex.synchronize do
      @channels[ch].close
      @channels.tap { |hs| hs.delete(ch) }
    end

    puts "Left channel #{channel}."
  end

  def command_show
    print_messages
  end

  def command_exit
    print 'Closing connections...'
    @mutex.synchronize do
      @producer.close
      @channels.each do |key, ch|
        ch.close
      end
    end
    puts 'Done. Bye!'
  end
end

# the 'main' part
host, port, nick = ARGV

client = Client.new({
  :host => host,
  :port => port.to_i,
  :nick => nick
  })

listener = Thread.new {
  puts "Listener started."
  loop do
    begin
      client.fetch_messages
    rescue ChannelError
      sleep 3
    rescue => e
      puts "[ERROR] #{e.message}"
    end
    sleep 1
  end
}

puts "Connected as #{client.nick}"
loop do
  printf "[%s] > ", client.nick
  input = $stdin.gets.chomp

  begin
    client.process_command(input)
    if client.has_messages?
      client.print_messages
    end

    break if input.downcase.start_with?('/exit')
  rescue => e
    puts "[ERROR] #{e.message}"
  end
end
listener.exit
