require 'rails_helper'

RSpec.describe AgentBots::ReplyService do
  let(:account) do
    create(
      :account,
      name: 'Northwind',
      custom_attributes: { 'bot_description' => 'Sells maps' },
      internal_attributes: {
        'bot_website_summary' => 'Open weekdays. Maps start at ten dollars.',
        'bot_website_summary_domain' => 'northwind.test'
      }
    )
  end
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ANTHROPIC_API_KEY', nil).and_return('test-key')
    create(:message, conversation: conversation, message_type: :incoming, content: 'How much is a map?')
  end

  it 'sends the account company description, website summary, and recent messages' do
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
    expect(captured['system']).to include('Sells maps')
    expect(captured['system']).to include('Maps start at ten dollars.')
    expect(captured['system']).to include('say you will check')
    expect(captured.dig('messages', 0, 'content')).to include('Customer: How much is a map?')
  end

  it 'uses the account name when that account has no website summary' do
    account.update_columns(custom_attributes: {}, internal_attributes: {})
    captured = nil
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ content: [{ 'type' => 'text', 'text' => 'Hello' }] }.to_json)
    allow(Net::HTTP).to receive(:post) do |_uri, body, _headers|
      captured = JSON.parse(body)
      response
    end

    described_class.new(conversation: conversation.reload, content: 'Hello', sender_name: 'Ada').perform

    expect(captured['system']).to include('Northwind')
    expect(captured['system']).not_to include('Website text')
  end
end
