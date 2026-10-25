class WebsitePageFetcher
  PAGE_LIMIT = 4
  PAGE_TEXT_LIMIT = 2_000
  SUMMARY_LIMIT = 6_000
  READ_TIMEOUT = 8
  LINK_HINTS = %w[about service services product products pricing solutions].freeze

  def self.summary_for(domain)
    new(domain).summary
  end

  def initialize(domain)
    @domain = domain.to_s.downcase.delete_prefix('www.')
  end

  def summary
    return if @domain.blank?

    home_url = "https://#{@domain}"
    home_html = fetch_html(home_url)
    return if home_html.blank?

    pages = [page_text(home_html, home_url)]
    extra_links(home_html, home_url).first(PAGE_LIMIT - 1).each do |url|
      html = fetch_html(url)
      pages << page_text(html, url) if html.present?
    end

    pages.compact.join("\n\n").truncate(SUMMARY_LIMIT).presence
  end

  private

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
    Rails.logger.warn("Website fetch failed for #{url}: #{e.message}")
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
    host.to_s.downcase.delete_prefix('www.') == @domain
  end
end
