class Inboxes::BroadcastMessageService
  pattr_initialize [:inbox!, :content!, :sender!]

  def perform
    sent = 0
    inbox.contact_inboxes.find_each do |contact_inbox|
      sent += 1 if deliver(contact_inbox)
    end
    sent
  end

  private

  def deliver(contact_inbox)
    return false if contact_inbox.source_id.blank?

    conversation = contact_inbox.conversations.order(last_activity_at: :desc).first
    return false if conversation.blank?
    return false unless Conversations::MessageWindowService.new(conversation).can_reply?

    Messages::MessageBuilder.new(
      sender,
      conversation,
      ActionController::Parameters.new(content: content)
    ).perform
    true
  rescue StandardError => e
    Rails.logger.warn("[Inbox broadcast #{inbox.id}] contact inbox #{contact_inbox.id} failed: #{e.class}")
    false
  end
end