# frozen_string_literal: true

class Integrations::Facebook::MessageCreator
  attr_reader :response

  def initialize(response)
    @response = response
  end

  def perform
    # begin
    return if response.echo? && response.sent_from_chatwoot_app?

    if agent_message_via_echo?
      create_agent_message
    else
      create_contact_message
    end
    # rescue => e
    # ChatwootExceptionTracker.new(e).capture_exception
    # end
  end

  private

  def agent_message_via_echo?
    # echoes of chatwoot-sent messages are skipped in perform; a remaining echo means an agent
    # replied from the fb page directly (mobile / web messenger), so handle it as an agent message
    response.echo?
  end

  def create_agent_message
    Channel::FacebookPage.where(page_id: response.sender_id).each do |page|
      mb = Messages::Facebook::MessageBuilder.new(response, page.inbox, outgoing_echo: true)
      mb.perform
    end
  end

  def create_contact_message
    recipient_id = response.recipient_id.to_s
    pages = Channel::FacebookPage.where(page_id: recipient_id).to_a
    pages = [Channel::FacebookPage.order(:id).first].compact if pages.empty?

    pages.each do |page|
      Messages::Facebook::MessageBuilder.new(response, page.inbox).perform
    end
  end
end
