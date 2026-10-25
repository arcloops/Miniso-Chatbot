class WebsitePageFetcher
  PAGE_LIMIT = 4
  PAGE_TEXT_LIMIT = 6_000
  SUMMARY_LIMIT = 14_000
  READ_TIMEOUT = 6
  REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
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
    current = url
    4.times do
      response = HTTParty.get(
        current,
        headers: { 'User-Agent' => 'ArcloopsBot/1.0', 'Accept' => 'text/html' },
        timeout: READ_TIMEOUT,
        follow_redirects: false
      )
      if REDIRECT_CODES.include?(response.code.to_i)
        location = response.headers['location'].to_s
        return if location.blank?

        current = URI.join(current, location).to_s
        return unless allowed_host?(URI(current).host)

        next
      end

      return unless response.success?
      return unless allowed_host?(URI(current).host)

      body = response.body.to_s
      return if body.blank?

      return body.byteslice(0, 500_000)
    end
    nil
  rescue StandardError => e
    Rails.logger.warn("Website fetch failed for #{url}: #{e.message}")
    nil
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
