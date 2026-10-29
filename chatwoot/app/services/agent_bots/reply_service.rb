class AgentBots::ReplyService
  API_URL = 'https://api.anthropic.com/v1/messages'
  MODEL = 'claude-haiku-4-5'
  HISTORY_LIMIT = 6
  WEBSITE_SUMMARY_LIMIT = 12_000

  def initialize(conversation:, content:, sender_name: nil, image_note: nil, message: nil)
    @conversation = conversation
    @content = content
    @sender_name = sender_name
    @image_note = image_note
    @message = message
  end

  def perform
    refresh_website_knowledge
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
      max_tokens: 500,
      system: system_prompt,
      messages: [{ role: 'user', content: user_content }]
    }.to_json
  end

  def system_prompt
    return 'You are the Arcloops inbox assistant. Reply briefly and helpfully to the customer message.' if account.blank?

    parts = []
    parts << "You are the customer assistant for #{account.name}."
    parts << 'Answer from the company description, the daily product sheet, and the website text. ' \
             'For stock and prices, use the product sheet. Use the website for what the company does.'
    parts << if customer_photo.present?
               'The customer photo is attached to their message. Look at that photo. Do not say you cannot see it. ' \
                 'Use the photo only to choose a product sheet row. Price and stock come from that row. ' \
                 'If more than one row could be the item in the photo, ask which one and do not give a price.'
             elsif photo_message?
               'The customer sent a product photo. Choose the product only from the product sheet rows in this prompt. ' \
                 'Do not invent a product that is not listed. Price and stock come from the matching row.'
             else
               'A customer photo is only a way to choose a catalog row. Price, stock, and specifications come from that row. ' \
                 'If the photo matches more than one row, or none, ask a short question and do not give a price.'
             end
    parts << 'Do not give a generic reply when that text answers the question. If it does not contain the fact, ' \
             'say you will check and get back to them. Do not invent prices, policies, services, or stock.'
    parts << "Company description:\n#{account.bot_description}" if account.bot_description.present?
    sheet = product_sheet_text
    parts << sheet if sheet.present?
    summary = website_summary
    parts << "Website text:\n#{summary}" if summary.present?
    parts.join("\n\n")
  end

  def user_message
    parts = []
    parts << "Customer name: #{@sender_name}" if @sender_name.present?
    parts << "Company: #{account.name}" if account.present?
    transcript = recent_transcript
    parts << "Recent conversation:\n#{transcript}" if transcript.present?
    parts << "Customer photo clues: #{@image_note}" if photo_clues.present?
    parts << "Customer message: #{@content}"
    parts.join("\n\n")
  end

  def user_content
    text = user_message
    photo = customer_photo
    return text if photo.blank?

    [
      {
        type: 'image',
        source: {
          type: 'base64',
          media_type: photo[:content_type],
          data: Base64.strict_encode64(photo[:bytes])
        }
      },
      { type: 'text', text: "#{text}\n\nThe product photo is attached above. Identify that product from the product sheet." }
    ]
  end

  def customer_photo
    return @customer_photo if defined?(@customer_photo)

    @customer_photo = Accounts::CustomerImageNote.prepared_for(@message)
  end

  def photo_message?
    return false if @message.blank?

    @message.attachments.any? { |item| item.image? || item.file_type.to_s == 'image' }
  end

  def product_sheet_text
    query = [@content, *recent_customer_lines].compact.join("\n")
    Accounts::ProductSheetService.reply_text(
      account,
      query,
      image_note: @image_note,
      photo_attached: customer_photo.present? || photo_message?,
      image_visible: customer_photo.present?
    )
  rescue StandardError => e
    Rails.logger.warn("[AgentBots::ReplyService] product sheet failed: #{e.class}: #{e.message}")
    nil
  end

  def photo_clues
    return if @image_note.blank? || @image_note == Accounts::CustomerImageNote::UNREADABLE

    @image_note
  end

  def recent_customer_lines
    return [] if @conversation.blank?

    @conversation.messages.incoming.order(id: :desc).limit(4).pluck(:content)
  end

  def website_summary
    account.internal_attributes.to_h['bot_website_summary'].to_s.truncate(WEBSITE_SUMMARY_LIMIT).presence
  end

  def refresh_website_knowledge
    return if account.blank? || account.bot_website.blank?

    stored = account.internal_attributes.to_h
    return if stored['bot_website_summary'].present? && stored['bot_website_summary_domain'].to_s == account.bot_website

    Accounts::WebsiteSummaryService.new(account).perform
    account.reload
  rescue StandardError => e
    Rails.logger.warn("[AgentBots::ReplyService] website read failed: #{e.class}: #{e.message}")
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
