class AgentBots::ReplyService
  API_URL = 'https://api.anthropic.com/v1/messages'
  MODEL = 'claude-haiku-4-5'

  def initialize(conversation:, content:, sender_name: nil)
    @conversation = conversation
    @content = content
    @sender_name = sender_name
  end

  def perform
    api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
    return if api_key.blank?

    response = Net::HTTP.post(
      URI(API_URL),
      request_body,
      {
        'content-type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => '2023-06-01'
      }
    )
    return unless response.is_a?(Net::HTTPSuccess)

    text_from(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.warn("[AgentBots::ReplyService] #{e.class}: #{e.message}")
    nil
  end

  private

  def request_body
    {
      model: MODEL,
      max_tokens: 1024,
      system: 'You are the Arcloops inbox assistant. Reply briefly and helpfully to the customer message.',
      messages: [{ role: 'user', content: user_message }]
    }.to_json
  end

  def user_message
    name = @sender_name.present? ? "Customer name: #{@sender_name}\n" : ''
    "#{name}Customer message: #{@content}"
  end

  def text_from(body)
    Array(body['content']).filter_map { |block| block['text'] if block['type'] == 'text' }.join.strip.presence
  end
end
