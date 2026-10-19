class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :events

  def events
    payload = webhook_payload
    object = payload['object'].to_s
    if object.casecmp('instagram').zero?
      entries = Array(payload['entry'])
      if contains_echo_event?(entries)
        # Add delay to prevent race condition where echo arrives before send message API completes
        # This avoids duplicate messages when echo comes early during API processing
        ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(entries)
      else
        ::Webhooks::InstagramEventsJob.perform_later(entries)
      end

      render json: :ok
    elsif object.casecmp('page').zero?
      # The page subscription for Messenger is pointed at this callback.
      # Save the text in this request so it does not depend on a second queue pickup.
      store_messenger_page_events(payload)
      render json: :ok
    else
      Rails.logger.warn("Message is not received from the instagram webhook event: #{object}")
      head :unprocessable_entity
    end
  end

  private

  def store_messenger_page_events(payload)
    Array(payload['entry']).each do |entry|
      next unless entry.is_a?(Hash)

      (Array(entry['messaging']) + Array(entry['standby'])).each do |messaging|
        next unless messaging.is_a?(Hash) && (messaging['message'] || messaging['postback'])

        ::Webhooks::FacebookEventsJob.perform_now({ 'messaging' => messaging }.to_json)
      end
    end
  end

  def contains_echo_event?(entries)
    entries.any? do |entry|
      next false unless entry.is_a?(Hash)

      Array(entry['messaging']).any? do |messaging|
        messaging.is_a?(Hash) && messaging.dig('message', 'is_echo').present?
      end
    end
  end

  def webhook_payload
    return @webhook_payload if defined?(@webhook_payload)

    parsed = JSON.parse(request.raw_post.presence || '{}')
    @webhook_payload = parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    @webhook_payload = {}
  end

  def valid_token?(token)
    # The Messenger page and the Instagram account can verify this same callback.
    [
      GlobalConfigService.load('IG_VERIFY_TOKEN', ''),
      GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', ''),
      GlobalConfigService.load('FB_VERIFY_TOKEN', '')
    ].any? { |expected| expected.present? && expected == token }
  end

  def meta_app_secrets
    [
      *instagram_channel_meta_app_secrets,
      GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil),
      GlobalConfigService.load('FB_APP_SECRET', nil)
    ]
  end

  def instagram_channel_meta_app_secrets
    instagram_channels_from_payload.flat_map { |channel| channel_meta_app_secrets(channel) }
  end

  def instagram_channels_from_payload
    Array(webhook_payload['entry']).flat_map do |entry|
      next [] unless entry.is_a?(Hash)

      instagram_ids_from_entry(entry).flat_map do |instagram_id|
        [
          Channel::Instagram.find_by(instagram_id: instagram_id),
          Channel::FacebookPage.find_by(instagram_id: instagram_id)
        ]
      end
    end.compact.uniq
  end

  def instagram_ids_from_entry(entry)
    messages = Array(entry['messaging']) + Array(entry['standby'])
    messages.filter_map { |messaging| instagram_id_from_messaging(messaging) if messaging.is_a?(Hash) }
  end

  def instagram_id_from_messaging(messaging)
    return messaging.dig('sender', 'id') if messaging.dig('message', 'is_echo').present?

    messaging.dig('recipient', 'id')
  end
end
