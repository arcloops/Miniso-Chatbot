require 'rails_helper'

describe Webhooks::AgentReplyJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, message_type: 'incoming', account: account, inbox: inbox, conversation: conversation, content: 'Hello') }
  let!(:agent_bot) { create(:agent_bot, account: account) }

  it 'replies on an inbox that has no bot attached' do
    allow(AgentBots::ReplyService).to receive(:new).and_return(instance_double(AgentBots::ReplyService, perform: 'Hi there'))
    builder = instance_double(Messages::MessageBuilder, perform: true)
    allow(Messages::MessageBuilder).to receive(:new).and_return(builder)

    described_class.perform_now({ 'id' => message.id })

    expect(Messages::MessageBuilder).to have_received(:new).with(
      agent_bot, conversation, { content: 'Hi there', message_type: 'outgoing' }
    )
    expect(message.reload.content_attributes['auto_reply_sent']).to be(true)
  end

  it 'does not reply twice for the same message' do
    message.update!(content_attributes: { 'auto_reply_sent' => true })
    expect(AgentBots::ReplyService).not_to receive(:new)

    described_class.perform_now({ 'id' => message.id })
  end
end
