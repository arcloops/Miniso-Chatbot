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
    sheet = @account.product_sheet || @account.build_product_sheet
    sheet.update!(
      filename: File.basename(upload.original_filename.to_s).slice(0, 180),
      headers: parsed[:headers],
      rows: parsed[:rows],
      row_count: parsed[:rows].size,
      truncated: parsed[:truncated]
    )
    sheet
  end

  def clear
    @account.product_sheet&.destroy!
  end

  def self.reply_text(account, query)
    sheet = AccountProductSheet.find_by(account_id: account.id)
    return if sheet.blank? || sheet.rows.blank?

    headers = Array(sheet.headers)
    matches = matching_rows(sheet.rows, query)
    updated = sheet.updated_at&.utc&.strftime('%d %b %Y')
    intro = "Product sheet #{sheet.filename}, updated #{updated}. Columns: #{headers.join(' | ')}."
    intro = "#{intro} The file had more products than could be saved, so only the first #{sheet.row_count} are here." if sheet.truncated

    if matches.empty?
      return "#{intro} #{sheet.row_count} products. No row matched this message. Do not invent stock or prices."
    end

    lines = matches.map { |row| Array(row).join(' | ') }
    "#{intro}\n#{lines.join("\n")}"
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
