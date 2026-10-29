class Accounts::ProductSheetService
  MATCH_LIMIT = 25
  STOPWORDS = %w[
    a an the and or to of for in on is it do you your we our have has this that with from
    please hello hi thanks thank what how much many price stock available availability
    product products item items any can could would there about me my
  ].freeze

  def initialize(account)
    @account = account
  end

  def replace(upload)
    raise Accounts::SpreadsheetReader::Error, 'Choose a CSV or Excel file.' if upload.blank?

    parsed = Accounts::SpreadsheetReader.read(upload.original_filename, upload.read)
    sheet = @account.product_sheets.create!(
      filename: safe_filename(upload.original_filename),
      headers: parsed[:headers],
      rows: parsed[:rows],
      row_count: parsed[:rows].size,
      truncated: parsed[:truncated]
    )
    begin
      store_embedded_images(sheet, parsed[:images])
      self.class.queue_image_index(sheet)
    rescue StandardError => e
      Rails.logger.warn("[ProductSheet] pictures not stored #{e.class}")
    end
    sheet
  end

  def safe_filename(name)
    File.basename(name.to_s).delete("\u0000").slice(0, 180).presence || 'products.csv'
  end

  def store_embedded_images(sheet, images)
    Array(images).each do |image|
      bytes = image[:bytes].to_s.b
      next if bytes.blank?

      digest = Digest::SHA256.hexdigest(bytes)
      record = sheet.product_images.create!(
        account_id: sheet.account_id,
        row_index: image[:row_index].to_i,
        source_digest: digest,
        content_hash: digest,
        status: 'pending'
      )
      io = StringIO.new(bytes)
      io.binmode
      record.file.attach(
        io: io,
        filename: "product-#{record.row_index}.#{image[:content_type].to_s.split('/').last}",
        content_type: image[:content_type]
      )
    end
  end

  def clear(sheet_id)
    @account.product_sheets.find(sheet_id).destroy!
  end

  def self.reply_text(account, query, image_note: nil, photo_attached: false, image_visible: nil)
    sheet = AccountProductSheet.where(account_id: account.id).newest_first.first
    return if sheet.blank? || sheet.rows.blank?

    visible = image_visible.nil? ? photo_attached : image_visible
    return photo_catalog(sheet, attached: visible) if photo_attached && image_note.blank?
    return visual_reply(sheet, image_note, photo_attached: photo_attached, image_visible: visible) if image_note.present?

    headers = Array(sheet.headers)
    matches = matching_rows(sheet.rows, query)
    updated = sheet.updated_at&.utc&.strftime('%d %b %Y')
    intro = "Product sheet #{sheet.filename}, updated #{updated}. Columns: #{headers.join(' | ')}."
    intro = "#{intro} The file had more products than could be saved, so only the first #{sheet.row_count} are here." if sheet.truncated

    if matches.empty?
      return "#{intro} #{sheet.row_count} products. No row matched this message. Do not invent stock or prices."
    end

    lines = matches.map { |row| public_cells(row).join(' | ') }
    "#{intro}\n#{lines.join("\n")}"
  end

  def self.visual_reply(sheet, image_note, photo_attached: false, image_visible: false)
    if image_note == Accounts::CustomerImageNote::UNREADABLE
      return photo_catalog(sheet, attached: image_visible) if photo_attached

      return 'The customer sent a photo that could not be read. Ask them to name the product. Do not give a price or stock count.'
    end

    pictures = AccountProductImage.readable.where(product_sheet_id: sheet.id).group_by(&:row_index)
    scored = Array(sheet.rows).each_with_index.filter_map do |row, index|
      cells = Array(row)
      next if cells.all? { |cell| cell.to_s.strip.blank? }

      summary = Array(pictures[index]).map(&:visual_summary).join(' ')
      score = term_score(image_note, "#{summary} #{cells.join(' ')}")
      [score, cells] if score.positive?
    end
    scored.sort_by! { |score, _row| -score }
    if scored.empty? || scored.first.first < 2
      return photo_catalog(sheet, attached: image_visible) if photo_attached
      if %w[pending processing].include?(sheet.image_status)
        return 'Product pictures from the sheet are still being read. Ask the customer for the product name. Do not give a price or stock count.'
      end

      return unmatched_photo(sheet)
    end

    top_score = scored.first.first
    chosen = scored.take_while { |score, _row| score >= top_score - 1 }.first(3)
    lines = chosen.map { |_score, row| public_cells(row).join(' | ') }
    intro = "Product sheet #{sheet.filename}. Columns: #{Array(sheet.headers).join(' | ')}."
    if chosen.one? && top_score >= 2
      "#{intro}\nConfirmed catalog row from the customer photo. The photo is attached. Use only this row for price and stock if it is the product in the photo:\n#{lines.first}"
    else
      "#{intro}\nPossible catalog rows from the customer photo. The photo is attached. Ask which one they mean before giving a price:\n#{lines.join("\n")}"
    end
  end

  def self.photo_catalog(sheet, attached:)
    rows = Array(sheet.rows).first(150)
    lines = rows.filter_map do |row|
      line = public_cells(row).reject(&:blank?).first(6).join(' | ')
      line.presence
    end
    intro = "Product sheet #{sheet.filename}. Columns: #{Array(sheet.headers).join(' | ')}."
    instruction = if attached
                    'The customer photo is attached. Find that exact product in the rows below. ' \
                      'Give the price and stock only from the matching row. Do not say you cannot see the photo. ' \
                      'If none of these rows is the product in the photo, ask for the product name.'
                  else
                    'The customer sent a product photo. Choose only from the rows below. Do not invent a product that is not listed. ' \
                      'If none of these rows is the item, ask for the product name.'
                  end
    "#{intro}\n#{instruction}\n#{lines.join("\n")}"
  end

  def self.unmatched_photo(sheet)
    "Product sheet #{sheet.filename} has #{sheet.row_count} products. The photo did not match one catalog item. " \
      'Ask the customer for the product name. Do not give a price or stock count.'
  end

  def self.public_cells(row)
    Array(row).map { |cell| cell.to_s.gsub(%r{https?://\S+}i, '').strip }
  end

  def self.term_score(note, blob)
    terms = note.to_s.downcase.scan(/[[:alnum:]]{3,}/).uniq - STOPWORDS - %w[unknown summary color label model photo picture image]
    text = blob.to_s.downcase
    terms.count { |term| text.match?(/\b#{Regexp.escape(term)}\b/) }
  end

  def self.queue_image_index(sheet)
    return unless sheet.has_attribute?(:image_status)

    found = Accounts::CatalogImageIndexer.targets(sheet)
    embedded = sheet.respond_to?(:product_images) ? sheet.product_images.where(status: 'pending').count : 0
    stats = { 'discovered' => found.size + embedded, 'indexed' => 0, 'reused' => 0, 'failed' => 0, 'skipped' => 0 }
    if found.empty? && embedded.zero?
      sheet.update!(image_status: 'none', image_stats: stats)
      return
    end

    sheet.update!(image_status: 'pending', image_stats: stats)
    Accounts::IndexProductImagesJob.perform_later(sheet.id)
  end

  def self.matching_rows(rows, query)
    terms = query.to_s.downcase.scan(/[[:alnum:]]{3,}/).uniq - STOPWORDS
    return [] if terms.empty?

    scored = rows.filter_map do |row|
      text = Array(row).join(' ').downcase
      score = terms.count { |term| text.include?(term) }
      [score, row] if score.positive?
    end
    scored.sort_by { |score, _row| -score }.first(MATCH_LIMIT).map(&:last)
  end
end
