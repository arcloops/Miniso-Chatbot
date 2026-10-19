class Facebook::RegisterWebhooksService
  PAGE_FIELDS = %w[
    messages message_deliveries message_echoes message_reads
    standby messaging_handovers messaging_postbacks
  ].freeze
  INSTAGRAM_FIELDS = %w[messages message_reactions messaging_seen].freeze

  def perform
    url = callback_url
    token = verify_token
    return if url.blank? || token.blank?

    register(config('FB_APP_ID'), config('FB_APP_SECRET'), 'page', PAGE_FIELDS, url, token)
    register(config('INSTAGRAM_APP_ID'), config('INSTAGRAM_APP_SECRET'), 'page', PAGE_FIELDS, url, token)
    register(config('INSTAGRAM_APP_ID'), config('INSTAGRAM_APP_SECRET'), 'instagram', INSTAGRAM_FIELDS, url, token)
  end

  private

  def register(app_id, app_secret, object_name, fields, url, token)
    return if app_id.blank? || app_secret.blank?

    version = config('FACEBOOK_API_VERSION').presence || 'v18.0'
    response = HTTParty.post(
      "https://graph.facebook.com/#{version}/#{app_id}/subscriptions",
      body: {
        object: object_name,
        callback_url: url,
        verify_token: token,
        fields: fields.join(','),
        access_token: "#{app_id}|#{app_secret}"
      }
    )
    return if response.success?

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : nil
    Rails.logger.warn("Messenger webhook registration for #{object_name} failed: #{error.presence || response.code}")
  rescue StandardError => e
    Rails.logger.warn("Messenger webhook registration for #{object_name} failed: #{e.message}")
  end

  def callback_url
    base = ENV.fetch('FRONTEND_URL', nil).to_s.chomp('/')
    return if base.blank?

    "#{base}/webhooks/instagram"
  end

  def verify_token
    config('IG_VERIFY_TOKEN').presence ||
      config('INSTAGRAM_VERIFY_TOKEN').presence ||
      config('FB_VERIFY_TOKEN').presence
  end

  def config(key)
    GlobalConfigService.load(key, '')
  end
end
