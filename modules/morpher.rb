module SerieBot
  module Morpher
    extend Discordrb::Commands::CommandContainer
    extend Discordrb::EventContainer
    # TODO: change the hell out of this
    class << self
        attr_accessor :original_channel
        attr_accessor :mirrored_channel
        attr_accessor :messages
    end
    Helper.load_morpher

    def self.setup_channels(event)
      if original_channel.nil? | mirrored_channel.nil?
        @original_channel = if Config.debug
                     # Testing server #announcements
                     event.bot.channel(278741282568798209, event.bot.server(254417537746337792))
                   else
                     # RiiConnect24 #announcements
                     event.bot.channel(206934926136705024, event.bot.server(206934458954153984))
                   end
        # ID of mirror server
        @mirrored_channel = event.bot.channel(278674706377211915, event.bot.server(278674706377211915))
      end
    end

    def self.create_embed(user, description)
      embed_sent = Discordrb::Webhooks::Embed.new
      embed_sent.title = 'New announcement!'
      embed_sent.description = description
      embed_sent.colour = '#FFEB3B'
      embed_sent.author = Discordrb::Webhooks::EmbedAuthor.new(name: user.name,
                                                               url: 'https://www.riiconnect24.net',
                                                               icon_url: Helper.avatar_url(user, 32))
      return embed_sent
    end

    message do |event|
      setup_channels(event)
      if event.channel == original_channel
        embed_to_send = create_embed(event.user, event.message.content)
        message_to_send = mirrored_channel.send_embed('', embed_to_send)

        # Store message under original id
        @messages[event.message.id] = {
          embed_sent: embed_to_send,
          message_sent: message_to_send.id
        }
      end
    end

    message_edit do |event|
      setup_channels(event)
      if event.channel == original_channel
        # Time to edit the message!
        message_data = @messages[event.message.id]
        if message_data.nil?
          mirrored_channel.send_embed('', create_embed(event.bot.profile, 'A message was edited but I was not able to see it.'))
        else
          embed = message_data[:embed_sent]
          embed.description = event.message.content
          mirror_message_id = message_data[:message_sent]
          mirrored_channel.message(mirror_message_id).edit('', embed)
        end
      end
    end

    message_delete do |event|
      setup_channels(event)
      if event.channel == original_channel
        # Time to remove the corresponding announcement.
        if @messages[event.id].nil?
          # We can assume this announcement wasn't synced, so no use trying to recover it.
          # Oh well
        else
          mirrored_channel.message(@messages[event.id][:message_sent]).delete
          @messages.delete(event.id)
        end
      end
    end

    # The following method syncs the announcement channel with the mirror.
    # It's not a command. Call it with eval: #{Config.prefix}eval Morpher.sync_announcements
    # Also, I hope you've already setup the channels and cleared the whole channel.
    def self.sync_announcements
      current_history = []

      # Start on first message
      offset_id = original_channel.history(1, 1, 1)[0].id # get first message id

      # Now let's dump!
      loop do
        # We can only go through 100 messages at a time, so grab 100.
        # We need to reverse it because it goes reverse in what we're doing.
        current_history = original_channel.history(100, nil, offset_id).reverse
        # Break if there are no other messages
        break if current_history == []

        # Mirror announcement + save it
        current_history.each do |message|
          next if message.nil?
          embed_to_send = create_embed(message.user, message.content)
          message_to_send = mirrored_channel.send_embed('', embed_to_send)

          # Store message under original id
          @messages[message.id] = {
              embed_sent: embed_to_send,
              message_sent: message_to_send.id
          }
        end

        puts current_history.length
        # Set offset ID to last message in history that we saw
        # (this is the last message sent - 1 since Ruby has array offsets of 0)
        offset_id = current_history[current_history.length - 1].id
      end
      Helper.save_morpher
      return 'Done!'
    end
  end
end