require 'rails_helper'

describe Facebook::StandbyEvents do
  it 'sends standby messages through the normal Messenger handler' do
    standby_message = {
      'sender' => { 'id' => 'user-1' },
      'recipient' => { 'id' => 'page-1' },
      'message' => { 'mid' => 'mid-1', 'text' => 'hello' }
    }
    events = { 'entry' => [{ 'id' => 'page-1', 'standby' => [standby_message] }] }
    allow(Facebook::Messenger::Bot).to receive(:receive)

    described_class.process(events)

    expect(Facebook::Messenger::Bot).to have_received(:receive).with(standby_message)
  end

  it 'ignores standby events that are not messages' do
    events = { 'entry' => [{ 'standby' => [{ 'delivery' => { 'watermark' => 1 } }] }] }
    allow(Facebook::Messenger::Bot).to receive(:receive)

    described_class.process(events)

    expect(Facebook::Messenger::Bot).not_to have_received(:receive)
  end
end
