class Webhooks::AgentReplyJob < ApplicationJob
  queue_as :high

  def perform(payload)
    message = find_message(payload)
    return if message.blank?

    message.reload
    message.attachments.reset
    return unless message.incoming? && !message.private?
    return if replied?(message)
    return if wait_for_photo(message, payload)

    content = reply_content(message)
    image_note = Accounts::CustomerImageNote.recent_for(message)
    return if content.blank? && image_note.blank?

    content = 'The customer sent a product photo.' if content.blank?

    # Hold the message until the reply exists so a second job cannot send another one.
    message.with_lock do
      return if replied?(message) || already_answered?(message)

      conversation = message.conversation
      agent_bot = agent_bot_for(conversation)
      reply = AgentBots::ReplyService.new(
        conversation: conversation,
        content: content,
        sender_name: message.sender.try(:name),
        image_note: image_note,
        message: message
      ).perform
      reply = 'Thanks for your message. How can we help you?' if reply.blank?

      if agent_bot.present?
        Messages::MessageBuilder.new(agent_bot, conversation, { content: reply, message_type: 'outgoing' }).perform
      else
        conversation.messages.create!(
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :outgoing,
          content: reply
        )
      end
      mark_replied(message)
    end
  end

  private

  def wait_for_photo(message, payload)
    return false unless photo_pending?(message)
    return false if payload['image_attempts'].to_i >= 2

    self.class.set(wait: 5.seconds).perform_later(
      payload.merge('id' => message.id, 'image_attempts' => payload['image_attempts'].to_i + 1)
    )
    true
  end

  def photo_pending?(message)
    images = message.attachments.select { |item| item.image? || item.file_type.to_s == 'image' }
    return true if images.blank? && message.content.blank? && message.attachments.blank?
    return false if images.blank?

    Accounts::CustomerImageNote.prepared_for(message).blank?
  end

  def find_message(payload)
    return Message.find_by(id: payload['id']) if payload['id'].present?

    account_id = payload.dig('account', 'id') || ENV.fetch('CHATWOOT_ACCOUNT_ID', nil)
    display_id = Integer(payload.dig('conversation', 'id'), exception: false)
    return if account_id.blank? || display_id.nil?

    conversation = Conversation.find_by(account_id: account_id, display_id: display_id)
    return if conversation.blank?

    content = payload['content'].to_s
    scope = conversation.messages.incoming
    scope.where(content: content).order(id: :desc).first || scope.order(id: :desc).first
  end

  def agent_bot_for(conversation)
    inbox = conversation.inbox
    return inbox.agent_bot if inbox.agent_bot_inbox&.active? && inbox.agent_bot.present?

    agent_bot_from_token || AgentBot.accessible_to(conversation.account).order(:id).first
  end

  def agent_bot_from_token
    token = ENV.fetch('CHATWOOT_BOT_ACCESS_TOKEN', nil)
    return if token.blank?

    AccessToken.find_by(token: token, owner_type: 'AgentBot')&.owner
  end

  def reply_content(message)
    text = message.content.to_s.strip
    return text if text.present?
    return 'The customer sent an attachment.' if message.attachments.any?

    nil
  end

  def replied?(message)
    message.content_attributes.is_a?(Hash) && message.content_attributes['auto_reply_sent']
  end

  def already_answered?(message)
    message.conversation.messages.outgoing.where('id > ?', message.id).exists?
  end

  def mark_replied(message)
    attributes = (message.content_attributes || {}).merge('auto_reply_sent' => true)
    message.update!(content_attributes: attributes)
  end
end
