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
      filename: File.basename(upload.original_filename.to_s).slice(0, 180),
      headers: parsed[:headers],
      rows: parsed[:rows],
      row_count: parsed[:rows].size,
      truncated: parsed[:truncated]
    )
    self.class.queue_image_index(sheet)
    sheet
  end

  def clear(sheet_id)
    @account.product_sheets.find(sheet_id).destroy!
  end

  def self.reply_text(account, query, image_note: nil)
    sheet = AccountProductSheet.where(account_id: account.id).newest_first.first
    return if sheet.blank? || sheet.rows.blank?
    return visual_reply(sheet, image_note) if image_note.present?

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

  def self.visual_reply(sheet, image_note)
    if image_note == Accounts::CustomerImageNote::UNREADABLE
      return 'The customer sent a photo that could not be read. Ask them to name the product. Do not give a price or stock count.'
    end

    images = AccountProductImage.readable.where(product_sheet_id: sheet.id).select(:row_index, :visual_summary)
    return unmatched_photo(sheet) if images.blank?

    scored = images.group_by(&:row_index).filter_map do |index, pictures|
      row = Array(sheet.rows[index])
      next if row.blank?

      blob = "#{pictures.map(&:visual_summary).join(' ')} #{row.join(' ')}"
      score = term_score(image_note, blob)
      [score, row] if score.positive?
    end
    scored.sort_by! { |score, _row| -score }
    return unmatched_photo(sheet) if scored.empty? || scored.first.first < 2

    top_score = scored.first.first
    chosen = scored.take_while { |score, _row| score >= top_score - 1 }.first(3)
    lines = chosen.map { |_score, row| public_cells(row).join(' | ') }
    intro = "Product sheet #{sheet.filename}. Columns: #{Array(sheet.headers).join(' | ')}."
    if chosen.one? && top_score >= 3
      "#{intro}\nConfirmed catalog row from the customer photo. Use only this row for price and stock:\n#{lines.first}"
    else
      "#{intro}\nPossible catalog rows from the customer photo. Ask which one they mean before giving a price:\n#{lines.join("\n")}"
    end
  end

  def self.unmatched_photo(sheet)
    "Product sheet #{sheet.filename} has #{sheet.row_count} products. The photo did not match one catalog item. " \
      'Ask the customer for the product name. Do not give a price or stock count.'
  end

  def self.public_cells(row)
    Array(row).map { |cell| cell.to_s.gsub(%r{https?://\S+}i, '').strip }
  end

  def self.term_score(note, blob)
    terms = note.to_s.downcase.scan(/[[:alnum:]]{4,}/).uniq - STOPWORDS - %w[unknown summary color label model photo picture image]
    text = blob.to_s.downcase
    terms.count { |term| text.include?(term) }
  end

  def self.queue_image_index(sheet)
    found = Accounts::CatalogImageIndexer.targets(sheet)
    stats = { 'discovered' => found.size, 'indexed' => 0, 'reused' => 0, 'failed' => 0, 'skipped' => 0 }
    if found.empty?
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
