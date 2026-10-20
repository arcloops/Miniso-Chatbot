class Webhooks::InstagramEventsJob < MutexApplicationJob
  queue_as :high
  # This lock is only a short race dampener for first-message conversation creation.
  # ContactInbox creation is already protected by a unique index, but conversation
  # lookup is `find active conversation || create`, so concurrent first messages from
  # the same IG contact can create duplicate conversations.
  #
  # ActiveJob retries are not FIFO, so a longer retry window does not preserve message
  # order. Use deterministic backoff so the final attempt happens after the 3s lock TTL,
  # then process without the lock instead of dropping the webhook.
  retry_on_lock_conflict wait: ->(executions) { executions.seconds }, attempts: 3, on_exhaustion: :process_without_lock

  # @return [Array] We will support further events like reaction or seen in future
  SUPPORTED_EVENTS = [:message, :read, :postback].freeze

  def perform(entries)
    @entries = entries

    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: contact_instagram_id, ig_account_id: ig_account_id)
    # Keep the lock TTL just long enough for the first job to fetch profile data and
    # create the contact/conversation. A longer TTL would add user-visible latency for
    # hot contacts without giving us ordering guarantees.
    with_lock(key, 3.seconds) do
      process_entries(entries)
    end
  end

  def process_without_lock(entries)
    Rails.logger.warn("[#{self.class.name}] Processing without lock after lock retry exhaustion")
    process_entries(entries)
  end

  # https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook
  def process_entries(entries)
    entries.each do |entry|
      process_single_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_single_entry(entry)
    if message_change_events?(entry)
      process_message_changes(entry)
      return
    end

    if test_event?(entry)
      process_test_event(entry)
      return
    end

    process_messages(entry)
  end

  def process_messages(entry)
    messages(entry).each do |messaging|
      deliver_messaging(messaging, entry[:id])
    end
  end

  # Instagram Login delivers real DMs inside changes[field=messages], not messaging.
  # Treating every changes payload as a test drops the text before a reply can be sent.
  def message_change_events?(entry)
    Array(entry[:changes]).any? { |change| message_change?(change) }
  end

  def process_message_changes(entry)
    Array(entry[:changes]).each do |change|
      next unless message_change?(change)

      messaging = change[:value].with_indifferent_access
      if messaging.dig(:sender, :id).to_s == '12334' && messaging.dig(:recipient, :id).to_s == '23245'
        Instagram::TestEventService.new(messaging).perform
        next
      end

      deliver_messaging(messaging, entry[:id])
    end
  end

  def message_change?(change)
    change.is_a?(Hash) && change[:field].to_s == 'messages' && change[:value].is_a?(Hash)
  end

  def deliver_messaging(messaging, entry_instagram_id)
    messaging = messaging.with_indifferent_access
    Rails.logger.info("Instagram Events Job Messaging: #{messaging}")

    channel = find_channel(instagram_id(messaging))
    channel = find_channel(entry_instagram_id) if channel.blank? && entry_instagram_id.present?
    return if channel.blank?

    return unless (event_name = event_name(messaging))

    send(event_name, messaging, channel)
  end

  def agent_message_via_echo?(messaging)
    messaging[:message].present? && messaging[:message][:is_echo].present?
  end

  def test_event?(entry)
    entry[:changes].present?
  end

  def process_test_event(entry)
    messaging = extract_messaging_from_test_event(entry)

    Instagram::TestEventService.new(messaging).perform if messaging.present?
  end

  def extract_messaging_from_test_event(entry)
    entry[:changes].first&.dig(:value) if entry[:changes].present?
  end

  def instagram_id(messaging)
    if agent_message_via_echo?(messaging)
      messaging[:sender][:id]
    else
      messaging[:recipient][:id]
    end
  end

  def ig_account_id
    @entries&.first&.dig(:id)
  end

  def contact_instagram_id
    entry = @entries&.first
    return nil unless entry

    # Handle both messaging and standby arrays
    messaging = (entry[:messaging].presence || entry[:standby] || []).first
    return nil unless messaging

    # For echo messages (outgoing from our account), use recipient's ID (the contact)
    # For incoming messages (from contact), use sender's ID (the contact)
    if messaging.dig(:message, :is_echo)
      messaging.dig(:recipient, :id)
    else
      messaging.dig(:sender, :id)
    end
  end

  def sender_id
    @entries&.dig(0, :messaging, 0, :sender, :id)
  end

  def find_channel(instagram_id)
    # There will be chances for the instagram account to be connected to a facebook page,
    # so we need to check for both instagram and facebook page channels
    # priority is for instagram channel which created via instagram login
    channel = Channel::Instagram.find_by(instagram_id: instagram_id)
    # A Facebook page that was connected as Instagram already has its own instagram id.
    # Never attach an Instagram webhook to the Messenger page.
    channel ||= Channel::FacebookPage.where.not(instagram_id: [nil, '']).find_by(instagram_id: instagram_id)
    channel ||= bind_single_instagram_channel(instagram_id)

    channel
  end

  # Instagram login can store a different id than the one Meta sends on the webhook.
  # With one connected Instagram inbox, attach that webhook to it so the message is not dropped.
  # Never write this id onto a Messenger page.
  def bind_single_instagram_channel(instagram_id)
    channels = Channel::Instagram.limit(2).to_a
    return unless channels.one?

    channel = channels.first
    return channel if instagram_id.blank? || channel.instagram_id.to_s == instagram_id.to_s

    Rails.logger.warn(
      "Instagram webhook id #{instagram_id} did not match inbox #{channel.instagram_id}. Using the connected inbox."
    )
    channel.update(instagram_id: instagram_id.to_s)
    channel
  rescue StandardError => e
    Rails.logger.warn("Could not attach Instagram webhook id #{instagram_id}: #{e.message}")
    Channel::Instagram.first
  end

  def event_name(messaging)
    SUPPORTED_EVENTS.find { |key| messaging.key?(key) }
  end

  def message(messaging, channel)
    if channel.is_a?(Channel::Instagram)
      ::Instagram::MessageText.new(messaging, channel).perform
    else
      ::Instagram::Messenger::MessageText.new(messaging, channel).perform
    end
  end

  def read(messaging, channel)
    # Use a single service to handle read status for both channel types since the params are same
    ::Instagram::ReadStatusService.new(params: messaging, channel: channel).perform
  end

  def postback(messaging, channel)
    postback_message = {
      mid: messaging[:postback][:mid],
      text: messaging[:postback][:title]
    }
    message(messaging.merge(message: postback_message), channel)
  end

  def messages(entry)
    Array(entry[:messaging]) + Array(entry[:standby])
  end
end

# Actual response from Instagram webhook (both via Facebook page and Instagram direct)
# [
#   {
#     "time": <timestamp>,
#     "id": <INSTAGRAM_USER_ID>,
#     "messaging": [
#       {
#         "sender": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "recipient": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "timestamp": <timestamp>,
#         "message": {
#           "mid": <MESSAGE_ID>,
#           "text": <MESSAGE_TEXT>
#         }
#       }
#     ]
#   }
# ]

# Instagram's webhook via Instagram direct testing quirk: Test payloads vs Actual payloads
# When testing in Facebook's developer dashboard, you'll get a Page-style
# payload with a "changes" object. But don't be fooled! Real Instagram DMs
# arrive in the familiar Messenger format with a "messaging" array.
# This apparent inconsistency is actually by design - Instagram's webhooks
# use different formats for testing vs production to maintain compatibility
# with both Instagram Direct and Facebook Page integrations.
# See: https://developers.facebook.com/docs/instagram-platform/webhooks#event-notifications

# Test response from via Instagram direct
# [
#   {
#     "id": "0",
#     "time": <timestamp>,
#     "changes": [
#       {
#         "field": "messages",
#         "value": {
#           "sender": {
#             "id": "12334"
#           },
#           "recipient": {
#             "id": "23245"
#           },
#           "timestamp": "1527459824",
#           "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#           }
#         }
#       }
#     ]
#   }
# ]

# Test response via Facebook page
# [
#   {
#     "time": <timestamp>,,
#     "id": "0",
#     "messaging": [
#       {
#         "sender": {
#           "id": "12334"
#         },
#         "recipient": {
#           "id": "23245"
#         },
#         "timestamp": <timestamp>,
#         "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#         }
#       }
#     ]
#   }
# ]
