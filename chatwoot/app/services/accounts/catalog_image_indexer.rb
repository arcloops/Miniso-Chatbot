class Accounts::CatalogImageIndexer
  MAX_IMAGES = 80
  IMAGE_HEADER = /image|photo|picture|thumbnail|\bimg\b/i
  URL_PATTERN = %r{https?://[^\s,|]+}i

  def self.targets(sheet)
    new(sheet.id).targets
  end

  def initialize(sheet_id)
    @sheet = AccountProductSheet.find_by(id: sheet_id)
  end

  def perform
    return if @sheet.blank?

    found = targets
    if found.empty?
      @sheet.update!(image_status: 'none', image_stats: empty_stats)
      return
    end

    @sheet.update!(image_status: 'processing', image_stats: empty_stats.merge('discovered' => found.size))
    stats = index(found)
    status = if stats['indexed'].zero? && stats['reused'].zero? && stats['failed'].positive?
               'failed'
             else
               'completed'
             end
    @sheet.update!(image_status: status, image_stats: stats)
  rescue StandardError => e
    Rails.logger.warn("[CatalogImageIndexer] sheet=#{@sheet&.id} #{e.class}")
    @sheet&.update!(image_status: 'failed', image_stats: (@sheet.image_stats || {}).merge('error' => 'failed'))
  end

  def targets
    return [] if @sheet.blank?

    headers = Array(@sheet.headers)
    image_columns = headers.each_index.select { |index| headers[index].to_s.match?(IMAGE_HEADER) }
    found = []
    Array(@sheet.rows).each_with_index do |row, row_index|
      cells = image_columns.any? ? image_columns.filter_map { |index| row[index] } : Array(row)
      cells.join("\n").scan(URL_PATTERN).each do |url|
        next unless image_url?(url, image_columns.any?)

        found << { row_index: row_index, url: url }
      end
    end
    found.uniq { |item| [item[:row_index], item[:url]] }
  end

  private

  def index(found)
    stats = empty_stats.merge('discovered' => found.size, 'skipped' => [found.size - MAX_IMAGES, 0].max)
    seen = {}
    found.first(MAX_IMAGES).each do |target|
      digest = Digest::SHA256.hexdigest(target[:url])
      cached = seen[digest] || cached_source(digest)
      if cached
        copy_image(target, digest, cached)
        seen[digest] = cached
        stats['reused'] += 1
        next
      end

      fetched = Accounts::SafeImageFetch.fetch(target[:url])
      if fetched.nil?
        record(target, digest, status: 'failed', failure_reason: 'unreachable')
        stats['failed'] += 1
        next
      end

      content_hash = Digest::SHA256.hexdigest(fetched[:bytes])
      cached_bytes = cached_content(content_hash)
      if cached_bytes
        copy_image(target, digest, cached_bytes, content_hash)
        seen[digest] = cached_bytes
        stats['reused'] += 1
        next
      end

      described = Accounts::ImageDescriber.describe(fetched[:bytes], fetched[:content_type])
      if described.nil?
        record(target, digest, content_hash: content_hash, status: 'failed', failure_reason: 'unreadable')
        stats['failed'] += 1
        next
      end

      saved = record(
        target,
        digest,
        content_hash: content_hash,
        status: 'completed',
        visual_summary: described[:summary],
        visual_attributes: described.slice(:color, :label, :model).compact
      )
      seen[digest] = saved
      stats['indexed'] += 1
    end
    Rails.logger.info(
      "[CatalogImageIndexer] sheet=#{@sheet.id} discovered=#{stats['discovered']} indexed=#{stats['indexed']} " \
      "reused=#{stats['reused']} failed=#{stats['failed']}"
    )
    stats
  end

  def image_url?(url, header_column)
    return true if header_column

    path = URI.parse(url).path.to_s.downcase
    path.match?(/\.(jpe?g|png|gif|webp)\z/)
  rescue URI::InvalidURIError
    false
  end

  def cached_source(digest)
    AccountProductImage.readable.where(account_id: @sheet.account_id, source_digest: digest).order(id: :desc).first
  end

  def cached_content(content_hash)
    AccountProductImage.readable.where(account_id: @sheet.account_id, content_hash: content_hash).order(id: :desc).first
  end

  def copy_image(target, digest, cached, content_hash = cached.content_hash)
    record(
      target,
      digest,
      content_hash: content_hash,
      status: 'completed',
      visual_summary: cached.visual_summary,
      visual_attributes: cached.visual_attributes
    )
  end

  def record(target, digest, **attrs)
    @sheet.product_images.create!(
      {
        account_id: @sheet.account_id,
        row_index: target[:row_index],
        source_digest: digest
      }.merge(attrs)
    )
  end

  def empty_stats
    { 'discovered' => 0, 'indexed' => 0, 'reused' => 0, 'failed' => 0, 'skipped' => 0 }
  end
end
