require 'rails_helper'

RSpec.describe AgentBots::ReplyService do
  let(:account) { create(:account) }
  let(:company) do
    create(
      :company,
      account: account,
      name: 'Northwind',
      description: 'Sells maps',
      additional_attributes: { 'website_summary' => 'Open weekdays. Maps start at ten dollars.' }
    )
  end
  let(:contact) { create(:contact, account: account, company: company) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return('test-key')
    create(:message, conversation: conversation, message_type: :incoming, content: 'How much is a map?')
  end

  it 'sends the company description, website summary, and recent messages' do
    captured = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ content: [{ 'type' => 'text', 'text' => 'Maps start at ten dollars.' }] }.to_json)
    allow(Net::HTTP).to receive(:post) do |_uri, body, _headers|
      captured = JSON.parse(body)
      response
    end

    result = described_class.new(conversation: conversation, content: 'How much is a map?', sender_name: 'Ada').perform

    expect(result).to eq('Maps start at ten dollars.')
    expect(captured['system']).to include('Northwind')
    expect(captured['system']).to include('say you will check')
    user_text = captured.dig('messages', 0, 'content')
    expect(user_text).to include('Sells maps')
    expect(user_text).to include('Maps start at ten dollars.')
    expect(user_text).to include('Customer: How much is a map?')
  end

  it 'keeps the general assistant prompt when the contact has no company' do
    conversation.contact.update!(company: nil)
    captured = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ content: [{ 'type' => 'text', 'text' => 'Hello' }] }.to_json)
    allow(Net::HTTP).to receive(:post) do |_uri, body, _headers|
      captured = JSON.parse(body)
      response
    end

    described_class.new(conversation: conversation.reload, content: 'Hello', sender_name: 'Ada').perform

    expect(captured['system']).to eq('You are the Arcloops inbox assistant. Reply briefly and helpfully to the customer message.')
    expect(captured.dig('messages', 0, 'content')).not_to include('Website summary')
  end
end
