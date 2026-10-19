class Instagram::EnsureAppWebhookService
  FIELDS = %w[messages message_reactions messaging_seen].freeze

  def perform
    return if Channel::Instagram.none?

    app_id = config('INSTAGRAM_APP_ID')
    app_secret = config('INSTAGRAM_APP_SECRET')
    callback = callback_url
    token = verify_token
    return if app_id.blank? || app_secret.blank? || callback.blank? || token.blank?

    version = config('INSTAGRAM_API_VERSION').presence || 'v22.0'
    response = HTTParty.post(
      "https://graph.facebook.com/#{version}/#{app_id}/subscriptions",
      body: {
        object: 'instagram',
        callback_url: callback,
        verify_token: token,
        fields: FIELDS.join(','),
        access_token: "#{app_id}|#{app_secret}"
      }
    )
    return if response.success?

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : nil
    Rails.logger.warn("Instagram webhook registration failed: #{error.presence || response.code}")
  rescue StandardError => e
    Rails.logger.warn("Instagram webhook registration failed: #{e.message}")
  end

  private

  def callback_url
    base = ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
    return if base.blank?

    "#{base}/webhooks/instagram"
  end

  def verify_token
    config('INSTAGRAM_VERIFY_TOKEN').presence ||
      config('IG_VERIFY_TOKEN').presence ||
      config('FB_VERIFY_TOKEN').presence
  end

  def config(key)
    GlobalConfigService.load(key, '')
  end
end
