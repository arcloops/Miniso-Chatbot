class AgentBots::ReplyService
  API_URL = 'https://api.anthropic.com/v1/messages'
  MODEL = 'claude-haiku-4-5'
  HISTORY_LIMIT = 6
  WEBSITE_SUMMARY_LIMIT = 4_000

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
      max_tokens: 300,
      system: system_prompt,
      messages: [{ role: 'user', content: user_message }]
    }.to_json
  end

  def system_prompt
    if account.present?
      "You are the assistant for #{account.name}. Reply briefly. Use the company description and website " \
        'summary when they answer the question. If that material does not cover the question, say you will check ' \
        'and get back to them. Do not invent prices, policies, or services.'
    else
      'You are the Arcloops inbox assistant. Reply briefly and helpfully to the customer message.'
    end
  end

  def user_message
    parts = []
    parts << "Customer name: #{@sender_name}" if @sender_name.present?
    if account.present?
      parts << "Company: #{account.name}"
      parts << "Company description: #{account.bot_description}" if account.bot_description.present?
      summary = account.internal_attributes.to_h['bot_website_summary'].to_s.truncate(WEBSITE_SUMMARY_LIMIT)
      parts << "Website summary:\n#{summary}" if summary.present?
    end
    transcript = recent_transcript
    parts << "Recent conversation:\n#{transcript}" if transcript.present?
    parts << "Customer message: #{@content}"
    parts.join("\n\n")
  end

  def account
    return if @conversation.blank?

    @account ||= @conversation.account
  end

  def recent_transcript
    return if @conversation.blank?

    @conversation.messages
                 .where(private: false)
                 .where.not(message_type: :activity)
                 .order(id: :desc)
                 .limit(HISTORY_LIMIT)
                 .reverse
                 .filter_map { |message| transcript_line(message) }
                 .join("\n")
                 .presence
  end

  def transcript_line(message)
    text = message.content.to_s.strip
    return if text.blank?

    speaker = message.incoming? ? 'Customer' : 'Assistant'
    "#{speaker}: #{text.truncate(400)}"
  end

  def text_from(body)
    Array(body['content']).filter_map { |block| block['text'] if block['type'] == 'text' }.join.strip.presence
  end
end
