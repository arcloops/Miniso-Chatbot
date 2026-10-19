module InstagramConcern
  extend ActiveSupport::Concern

  def instagram_client
    ::OAuth2::Client.new(
      client_id,
      client_secret,
      {
        site: 'https://api.instagram.com',
        authorize_url: 'https://www.instagram.com/oauth/authorize',
        token_url: 'https://api.instagram.com/oauth/access_token',
        auth_scheme: :request_body,
        token_method: :post
      }
    )
  end

  private

  def client_id
    GlobalConfigService.load('INSTAGRAM_APP_ID', nil)
  end

  def client_secret
    GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def exchange_for_long_lived_token(short_lived_token)
    params = {
      grant_type: 'ig_exchange_token',
      client_secret: client_secret,
      access_token: short_lived_token
    }
    version = GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')
    endpoints = [
      "https://graph.instagram.com/#{version}/access_token",
      'https://graph.instagram.com/access_token'
    ].uniq

    endpoints.each do |endpoint|
      %i[get post].each do |http_method|
        result = token_exchange_request(endpoint, params, http_method)
        return result if result
      end
    end

    Rails.logger.warn('Instagram refused the long-lived token exchange. Creating the inbox with the login token.')
    { 'access_token' => short_lived_token, 'expires_in' => 3_600 }
  end

  def fetch_instagram_user_details(access_token)
    Instagram::UserDetailsService.new(access_token: access_token).perform
  end

  def token_exchange_request(endpoint, params, http_method)
    response = if http_method == :post
                 HTTParty.post(endpoint, body: params, headers: { 'Accept' => 'application/json' })
               else
                 HTTParty.get(endpoint, query: params, headers: { 'Accept' => 'application/json' })
               end
    return JSON.parse(response.body) if response.success?

    Rails.logger.error "Failed to exchange token via #{http_method.to_s.upcase} #{endpoint}. Status: #{response.code}, Body: #{response.body}"
    return nil if response.body.to_s.include?('Unsupported request - method type')

    raise "Failed to exchange token: #{response.body}"
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
