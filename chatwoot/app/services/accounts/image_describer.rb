class Accounts::ImageDescriber
  API_URL = 'https://api.anthropic.com/v1/messages'
  MODEL = 'claude-haiku-4-5'
  PROMPT = <<~TEXT.squish
    Look at this product photo. Reply with exactly these four lines and nothing else.
    Summary: one sentence about appearance, packaging, and visible variant.
    Color: the main colors, or unknown.
    Label: readable brand or product words, or unknown.
    Model: a visible model or sku, or unknown.
    Do not guess a price, stock count, or specification that is not printed on the item.
  TEXT

  def self.describe(bytes, content_type)
    new(bytes, content_type).describe
  end

  def self.prepare(bytes, content_type)
    new(bytes, content_type).prepare
  end

  def initialize(bytes, content_type)
    @bytes = bytes
    @content_type = content_type
  end

  def prepare
    shrink
  end

  def describe
    prepared = shrink
    return if prepared.nil?

    api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
    return if api_key.blank?

    response = Net::HTTP.post(
      URI(API_URL),
      request_body(prepared),
      {
        'content-type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => '2023-06-01'
      }
    )
    return unless response.is_a?(Net::HTTPSuccess)

    parse(text_from(JSON.parse(response.body)))
  rescue StandardError => e
    Rails.logger.warn("[ImageDescriber] #{e.class}")
    nil
  end

  private

  def request_body(prepared)
    {
      model: MODEL,
      max_tokens: 180,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: prepared[:content_type],
                data: Base64.strict_encode64(prepared[:bytes])
              }
            },
            { type: 'text', text: PROMPT }
          ]
        }
      ]
    }.to_json
  end

  def shrink
    shrunk = thumbnail
    return shrunk if shrunk

    type = Accounts::SafeImageFetch.image_type(@bytes.to_s.b)
    return if type.blank? || @bytes.bytesize > 3_500_000

    { bytes: @bytes, content_type: type }
  end

  def thumbnail
    require 'vips'
    image = Vips::Image.new_from_buffer(@bytes, '')
    image = image.thumbnail_image(512, size: :down)
    bytes = image.write_to_buffer('.jpg', Q: 60)
    return if bytes.bytesize > 400_000

    { bytes: bytes, content_type: 'image/jpeg' }
  rescue StandardError
    nil
  end

  def parse(text)
    return if text.blank?

    fields = {}
    text.each_line do |line|
      key, value = line.split(':', 2)
      next if key.blank? || value.blank?

      fields[key.strip.downcase] = value.strip
    end
    summary = fields['summary'].presence || text.truncate(400)
    color = usable(fields['color'])
    label = usable(fields['label'])
    model = usable(fields['model'])
    searchable = [summary, color, label, model].compact.join(' ')
    { summary: searchable.truncate(500), color: color, label: label, model: model }
  end

  def usable(value)
    cleaned = value.to_s.strip
    return if cleaned.blank? || cleaned.casecmp('unknown').zero?

    cleaned.truncate(120)
  end

  def text_from(body)
    Array(body['content']).filter_map { |block| block['text'] if block['type'] == 'text' }.join.strip.presence
  end
end
