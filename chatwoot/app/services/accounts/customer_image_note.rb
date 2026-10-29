class Accounts::CustomerImageNote
  UNREADABLE = 'The photo could not be read. Ask the customer to name the product. Do not give a price or stock count.'.freeze

  def self.remember(message)
    return if message.blank?

    cached = message.content_attributes.to_h['catalog_image_note']
    return cached if cached.present?

    attachment = message.attachments.detect { |item| item.image? && (item.file.attached? || item.external_url.present?) }
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
      return if blob.byte_size > Accounts::SafeImageFetch::MAX_BYTES

      return [blob.download, blob.content_type]
    end

    fetched = Accounts::SafeImageFetch.fetch(attachment.external_url)
    return if fetched.nil?

    [fetched[:bytes], fetched[:content_type]]
  end
end
