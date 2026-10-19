class Webhooks::AgentReplyJob < ApplicationJob
  queue_as :high

  def perform(payload)
    content = payload['content'].to_s.strip
    display_id = Integer(payload.dig('conversation', 'id'), exception: false)
    return if content.blank? || display_id.nil?

    account_id = ENV.fetch('CHATWOOT_ACCOUNT_ID', nil)
    conversation = Conversation.find_by(account_id: account_id, display_id: display_id)
    agent_bot = agent_bot_from_token
    return if conversation.blank? || agent_bot.blank?

    reply = AgentBots::ReplyService.new(
      conversation: conversation,
      content: content,
      sender_name: payload.dig('sender', 'name')
    ).perform
    return if reply.blank?

    Messages::MessageBuilder.new(agent_bot, conversation, { content: reply, message_type: 'outgoing' }).perform
  end

  private

  def agent_bot_from_token
    token = ENV.fetch('CHATWOOT_BOT_ACCESS_TOKEN', nil)
    return if token.blank?

    AccessToken.find_by(token: token, owner_type: 'AgentBot')&.owner
  end
end
