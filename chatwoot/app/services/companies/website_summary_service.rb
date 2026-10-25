class Companies::WebsiteSummaryService
  PAGE_LIMIT = 4
  PAGE_TEXT_LIMIT = 2_000
  SUMMARY_LIMIT = 6_000
  READ_TIMEOUT = 8
  LINK_HINTS = %w[about service services product products pricing solutions].freeze

  def initialize(company)
    @company = company
  end

  def perform
    return clear_summary if @company.domain.blank?

    summary = build_summary
    if summary.blank?
      clear_summary if stored_domain != @company.domain
      return
    end

    store_summary(summary)
  end

  private

  def build_summary
    home_url = "https://#{@company.domain}"
    home_html = fetch_html(home_url)
    return if home_html.blank?

    pages = [page_text(home_html, home_url)]
    extra_links(home_html, home_url).first(PAGE_LIMIT - 1).each do |url|
      html = fetch_html(url)
      pages << page_text(html, url) if html.present?
    end

    pages.compact.join("\n\n").truncate(SUMMARY_LIMIT).presence
  end

  def fetch_html(url)
    response = HTTParty.get(
      url,
      headers: { 'User-Agent' => 'ArcloopsBot/1.0', 'Accept' => 'text/html' },
      timeout: READ_TIMEOUT,
      follow_redirects: true
    )
    return unless response.success?
    return unless allowed_host?(response_host(response, url))

    body = response.body.to_s
    return if body.blank?

    body.byteslice(0, 500_000)
  rescue StandardError => e
    Rails.logger.warn("Company website fetch failed for #{url}: #{e.message}")
    nil
  end

  def response_host(response, url)
    request = response.request
    uri = request.last_uri if request.respond_to?(:last_uri)
    uri ||= request.uri if request.respond_to?(:uri)
    uri&.host || URI(url).host
  rescue StandardError
    URI(url).host
  end

  def extra_links(html, base_url)
    base = URI.parse(base_url)
    Nokogiri::HTML(html).css('a[href]').filter_map do |anchor|
      href = anchor['href'].to_s
      next if href.blank? || href.match?(/\A(#|mailto:|tel:|javascript:)/i)

      uri = URI.join(base, href)
      next unless uri.is_a?(URI::HTTP)
      next unless allowed_host?(uri.host)
      next unless LINK_HINTS.any? { |hint| uri.path.to_s.downcase.include?(hint) }

      uri.fragment = nil
      uri.query = nil
      uri.to_s
    end.uniq
  rescue URI::InvalidURIError, ArgumentError
    []
  end

  def page_text(html, url)
    document = Nokogiri::HTML(html)
    document.css('script, style, noscript, svg').remove
    text = document.at('body')&.text.to_s.gsub(/\s+/, ' ').strip
    return if text.blank?

    "#{url}\n#{text.truncate(PAGE_TEXT_LIMIT)}"
  end

  def allowed_host?(host)
    normalized = host.to_s.downcase.delete_prefix('www.')
    domain = @company.domain.to_s.downcase.delete_prefix('www.')
    normalized == domain
  end

  def stored_domain
    @company.additional_attributes['website_summary_domain']
  end

  def store_summary(summary)
    attributes = (@company.additional_attributes || {}).merge(
      'website_summary' => summary,
      'website_summary_domain' => @company.domain
    )
    @company.update_columns(additional_attributes: attributes, updated_at: Time.current)
  end

  def clear_summary
    return if @company.additional_attributes.blank?
    return if @company.additional_attributes['website_summary'].blank? && stored_domain.blank?

    attributes = @company.additional_attributes.except('website_summary', 'website_summary_domain')
    @company.update_columns(additional_attributes: attributes, updated_at: Time.current)
  end
end
