class Webhooks::AgentController < ActionController::API
  def create
    secret = ENV.fetch('CHATWOOT_BOT_WEBHOOK_SECRET', nil)
    return head :service_unavailable if secret.blank?
    return head :unauthorized unless signature_matches?(secret)

    payload = params.to_unsafe_hash
    Webhooks::AgentReplyJob.perform_later(payload) if incoming_message?(payload)
    head :ok
  end

  private

  def incoming_message?(payload)
    return false unless payload['event'].to_s == 'message_created'
    return false if ActiveModel::Type::Boolean.new.cast(payload['private'])

    message_type = payload['message_type']
    message_type.to_s == 'incoming' || message_type.to_i.zero? && message_type.to_s == '0'
  end

  def signature_matches?(secret)
    timestamp = request.headers['X-Chatwoot-Timestamp'].to_s
    signature = request.headers['X-Chatwoot-Signature'].to_s
    return false if timestamp.blank? || signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{request.raw_post}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  rescue ArgumentError
    false
  end
end
