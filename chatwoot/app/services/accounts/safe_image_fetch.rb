class Accounts::SafeImageFetch
  MAX_BYTES = 1_500_000
  OPEN_TIMEOUT = 4
  READ_TIMEOUT = 8

  def self.fetch(url)
    new(url).fetch
  end

  def self.public_ip?(ip)
    addr = IPAddr.new(ip.to_s)
    return false if addr.loopback? || addr.private? || addr.link_local?
    return false if addr.ipv4? && (addr.to_s.start_with?('0.') || addr.to_s == '255.255.255.255')

    true
  rescue IPAddr::InvalidAddressError
    false
  end

  def initialize(url)
    @url = url.to_s.strip
  end

  def fetch(hops = 2)
    uri = parse_uri(@url)
    return if uri.nil?

    ip = public_ip_for(uri.host)
    return if ip.blank?

    response = request(uri, ip)
    return if response.nil?

    if redirect?(response) && hops.positive?
      location = response['location'].to_s
      return if location.blank?

      @url = URI.join(uri, location).to_s
      return fetch(hops - 1)
    end
    return unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s.b
    return if body.bytesize < 32 || body.bytesize > MAX_BYTES

    content_type = image_type(body)
    return if content_type.blank?

    { bytes: body, content_type: content_type }
  rescue StandardError => e
    Rails.logger.warn("[SafeImageFetch] #{e.class}")
    nil
  end

  private

  def parse_uri(value)
    uri = URI.parse(value)
    return unless uri.is_a?(URI::HTTP)
    return unless %w[http https].include?(uri.scheme)
    return if uri.host.blank? || uri.userinfo.present?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def public_ip_for(host)
    return if host.blank?
    return host if self.class.public_ip?(host) && host.match?(/\A\d{1,3}(\.\d{1,3}){3}\z/)
    return if host.match?(/\A\d/) && !self.class.public_ip?(host)

    addresses = Resolv.getaddresses(host)
    ip = addresses.find { |address| self.class.public_ip?(address) }
    ip if ip.present? && addresses.all? { |address| self.class.public_ip?(address) }
  rescue Resolv::ResolvError
    nil
  end

  def request(uri, ip)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = ip if http.respond_to?(:ipaddr=)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.use_ssl = uri.scheme == 'https'
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
    path = uri.request_uri.presence || '/'
    http.request(Net::HTTP::Get.new(path, { 'User-Agent' => 'ArcloopsBot/1.0', 'Accept' => 'image/*' }))
  end

  def redirect?(response)
    [301, 302, 303, 307, 308].include?(response.code.to_i)
  end

  def image_type(body)
    return 'image/jpeg' if body.byteslice(0, 3) == "\xFF\xD8\xFF".b
    return 'image/png' if body.byteslice(0, 8) == "\x89PNG\r\n\x1A\n".b
    return 'image/gif' if body.byteslice(0, 6) == 'GIF87a'.b || body.byteslice(0, 6) == 'GIF89a'.b
    return 'image/webp' if body.byteslice(0, 4) == 'RIFF'.b && body.byteslice(8, 4) == 'WEBP'.b

    nil
  end
end
