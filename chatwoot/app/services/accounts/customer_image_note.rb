class Accounts::CustomerImageNote
  UNREADABLE = 'The photo could not be read. Ask the customer to name the product. Do not give a price or stock count.'.freeze

  def self.remember(message)
    return if message.blank?

    cached = message.content_attributes.to_h['catalog_image_note']
    return cached if cached.present?

    attachment = message.attachments.detect { |item| usable_image?(item) }
    return if attachment.blank?

    described = describe(attachment)
    note = described.present? ? described[:summary] : UNREADABLE
    message.update!(content_attributes: message.content_attributes.to_h.merge('catalog_image_note' => note))
    note
  rescue StandardError => e
    Rails.logger.warn("[CustomerImageNote] #{e.class}")
    UNREADABLE
  end

  def self.recent_for(message)
    note = remember(message)
    return note if note.present?
    return if message.blank?

    message.conversation.messages.incoming.where('id < ?', message.id).order(id: :desc).limit(4).each do |earlier|
      cached = earlier.content_attributes.to_h['catalog_image_note']
      return cached if cached.present?
    end
    nil
  end

  def self.describe(attachment)
    bytes, content_type = bytes_for(attachment)
    return if bytes.blank?

    Accounts::ImageDescriber.describe(bytes, content_type)
  end

  def self.bytes_for(attachment)
    if attachment.file.attached?
      blob = attachment.file.blob
      return if blob.byte_size > Accounts::SafeImageFetch::SOURCE_MAX_BYTES

      bytes = blob.download.to_s.b
      content_type = Accounts::SafeImageFetch.image_type(bytes)
      return if content_type.blank?

      return [bytes, content_type]
    end

    fetched = Accounts::SafeImageFetch.fetch(attachment.external_url)
    return if fetched.nil?

    [fetched[:bytes], fetched[:content_type]]
  end

  def self.prepared_for(message)
    return if message.blank?

    attachment = message.attachments.detect { |item| usable_image?(item) }
    return if attachment.blank?

    bytes, content_type = bytes_for(attachment)
    return if bytes.blank?

    Accounts::ImageDescriber.prepare(bytes, content_type)
  rescue StandardError => e
    Rails.logger.warn("[CustomerImageNote] prepare #{e.class}")
    nil
  end

  def self.usable_image?(attachment)
    return false if attachment.blank?
    return true if attachment.image? && (attachment.file.attached? || attachment.external_url.present?)
    return false unless attachment.file.attached?

    type = attachment.file.content_type.to_s
    name = attachment.file.filename.to_s
    type.start_with?('image/') || name.match?(/\.(jpe?g|png|gif|webp)\z/i)
  end
end
