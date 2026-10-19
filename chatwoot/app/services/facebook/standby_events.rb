class Facebook::StandbyEvents
  def self.process(events)
    Array(events['entry']).each do |entry|
      Array(entry['standby']).each do |messaging|
        next unless messaging.is_a?(Hash) && (messaging['message'] || messaging['postback'])

        Facebook::Messenger::Bot.receive(messaging)
      end
    end
  end
end
