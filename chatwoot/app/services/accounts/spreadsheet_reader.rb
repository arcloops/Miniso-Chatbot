class Accounts::SpreadsheetReader
  class Error < StandardError; end

  MAX_BYTES = 5 * 1024 * 1024
  MAX_ROWS = 8_000
  MAX_COLUMNS = 16
  MAX_CELL = 80
  MAX_URL_CELL = 1_000

  def self.read(filename, body)
    new(filename, body).read
  end

  def initialize(filename, body)
    @filename = filename.to_s
    @body = body.to_s.b
  end

  def read
    raise Error, 'The file is empty.' if @body.empty?
    raise Error, 'The file must be 5 MB or smaller.' if @body.bytesize > MAX_BYTES

    table = xlsx? ? xlsx_table : csv_table
    normalize(table)
  end

  private

  def xlsx?
    extension = File.extname(@filename).downcase
    return true if extension == '.xlsx'
    return false if extension == '.csv'

    raise Error, 'Save the spreadsheet as .csv or .xlsx and upload that file.'
  end

  def csv_table
    require 'csv'
    text = @body.dup.force_encoding('UTF-8')
    text = text.encode('UTF-8', invalid: :replace, undef: :replace).sub(/\A\uFEFF/, '')
    first = text.lines.first.to_s
    col_sep = first.count(';') > first.count(',') ? ';' : ','
    CSV.parse(text, col_sep: col_sep, liberal_parsing: true)
  rescue CSV::MalformedCSVError
    raise Error, 'That CSV could not be read. Save it again from Excel and upload the new file.'
  end

  def xlsx_table
    entries = zip_entries
    sheet_name = first_sheet_name(entries)
    raise Error, 'The Excel file has no sheet.' if sheet_name.blank?

    strings = shared_strings(entries['xl/sharedStrings.xml'])
    sheet_rows(entries[sheet_name], strings)
  rescue Nokogiri::XML::SyntaxError, Zlib::Error
    raise Error, 'That Excel file could not be read. Save it as .xlsx and upload it again.'
  end

  def zip_entries
    require 'zlib'
    data = @body
    eocd = data.rindex("PK\x05\x06".b)
    raise Error, 'That Excel file could not be read. Save it as .xlsx and upload it again.' if eocd.nil?

    cd_offset = data.byteslice(eocd + 16, 4).unpack1('V')
    raise Error, 'This Excel file is too large to read.' if cd_offset == 0xFFFFFFFF

    entries = {}
    offset = cd_offset
    while offset + 46 <= data.bytesize && data.byteslice(offset, 4) == "PK\x01\x02".b
      header = data.byteslice(offset, 46)
      method = header.byteslice(10, 2).unpack1('v')
      compressed_size = header.byteslice(20, 4).unpack1('V')
      name_length = header.byteslice(28, 2).unpack1('v')
      extra_length = header.byteslice(30, 2).unpack1('v')
      comment_length = header.byteslice(32, 2).unpack1('v')
      local_offset = header.byteslice(42, 4).unpack1('V')
      name = data.byteslice(offset + 46, name_length).dup.force_encoding(Encoding::UTF_8)
      entries[name] = inflate_entry(data, local_offset, method, compressed_size)
      offset += 46 + name_length + extra_length + comment_length
    end
    entries
  end

  def inflate_entry(data, local_offset, method, compressed_size)
    local = data.byteslice(local_offset, 30)
    return if local.nil? || local.bytesize < 30

    name_length = local.byteslice(26, 2).unpack1('v')
    extra_length = local.byteslice(28, 2).unpack1('v')
    compressed = data.byteslice(local_offset + 30 + name_length + extra_length, compressed_size).to_s
    return compressed if method.zero?
    return if method != 8

    inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    inflater.inflate(compressed)
  ensure
    inflater&.close
  end

  def first_sheet_name(entries)
    workbook = entries['xl/workbook.xml'].to_s
    rels = entries['xl/_rels/workbook.xml.rels'].to_s
    return if workbook.blank? || rels.blank?

    require 'nokogiri'
    workbook_xml = Nokogiri::XML(workbook)
    workbook_xml.remove_namespaces!
    relation_id = workbook_xml.at('sheet')&.[]('id')
    rels_xml = Nokogiri::XML(rels)
    rels_xml.remove_namespaces!
    target = rels_xml.css('Relationship').find { |node| node['Id'] == relation_id }&.[]('Target')
    return if target.blank?

    target = target.sub(%r{\A/}, '')
    target = "xl/#{target}" unless target.start_with?('xl/')
    target
  end

  def shared_strings(xml)
    return [] if xml.blank?

    require 'nokogiri'
    document = Nokogiri::XML(xml)
    document.remove_namespaces!
    document.css('si').map { |item| item.xpath('.//t').map(&:text).join }
  end

  def sheet_rows(xml, strings)
    raise Error, 'The Excel file has no sheet.' if xml.blank?

    require 'nokogiri'
    document = Nokogiri::XML(xml)
    document.remove_namespaces!
    document.css('row').map { |row| cells_for(row, strings) }
  end

  def cells_for(row, strings)
    values = []
    row.css('c').each do |cell|
      index = column_index(cell['r'])
      next if index.nil? || index >= MAX_COLUMNS

      values[index] = cell_text(cell, strings)
    end
    values.map { |value| value.to_s }
  end

  def column_index(reference)
    letters = reference.to_s[/[A-Z]+/]
    return if letters.blank?

    letters.chars.reduce(0) { |number, letter| (number * 26) + (letter.ord - 64) } - 1
  end

  def cell_text(cell, strings)
    case cell['t']
    when 's'
      strings[cell.at('v')&.text.to_i].to_s
    when 'inlineStr'
      cell.xpath('.//t').map(&:text).join
    else
      number = cell.at('v')&.text.to_s
      number.sub(/\.0+\z/, '')
    end
  end

  def normalize(table)
    cleaned = Array(table).filter_map do |row|
      cells = Array(row).first(MAX_COLUMNS).map { |cell| clip_cell(cell) }
      cells if cells.any?(&:present?)
    end
    raise Error, 'The spreadsheet has no product rows.' if cleaned.size < 2

    width = cleaned.map(&:size).max
    headers = cleaned.first.fill('', cleaned.first.size...width).each_with_index.map do |cell, index|
      cell.presence || "Column #{index + 1}"
    end
    rows = cleaned.drop(1).map { |row| row.fill('', row.size...width) }
    truncated = rows.size > MAX_ROWS
    { headers: headers, rows: rows.first(MAX_ROWS), truncated: truncated }
  end

  def clip_cell(value)
    text = value.to_s.strip.gsub(/[ \t\f\v]+/, ' ')
    limit = text.match?(%r{https?://}i) ? MAX_URL_CELL : MAX_CELL
    text[0, limit]
  end
end
