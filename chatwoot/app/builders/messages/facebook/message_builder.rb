# This class creates both outgoing messages from chatwoot and echo outgoing messages based on the flag `outgoing_echo`
# Assumptions
# 1. Incase of an outgoing message which is echo, source_id will NOT be nil,
#    based on this we are showing "not sent from chatwoot" message in frontend
#    Hence there is no need to set user_id in message for outgoing echo messages.

class Messages::Facebook::MessageBuilder < Messages::Messenger::MessageBuilder
  attr_reader :response

  def initialize(response, inbox, outgoing_echo: false)
    super()
    @response = response
    @inbox = inbox
    @outgoing_echo = outgoing_echo
    @sender_id = (@outgoing_echo ? @response.recipient_id : @response.sender_id)
    @message_type = (@outgoing_echo ? :outgoing : :incoming)
    @attachments = (@response.attachments || [])
  end

  def perform
    ActiveRecord::Base.transaction do
      build_contact_inbox
      build_message
    end
  rescue Koala::Facebook::AuthenticationError => e
    Rails.logger.warn("Facebook authentication error for inbox: #{@inbox.id} with error: #{e.message}")
    Rails.logger.error e
    @inbox.channel.authorization_error!
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    true
  end

  private

  def build_contact_inbox
    @resolved_contact_params = contact_params
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: @sender_id,
      inbox: @inbox,
      contact_attributes: @resolved_contact_params
    ).perform
    apply_resolved_name
    schedule_name_refresh if Facebook::ContactProfileService.placeholder?(@contact_inbox.contact.name)
  end

  def apply_resolved_name
    resolved_name = @resolved_contact_params[:name]
    contact = @contact_inbox.contact
    return if Facebook::ContactProfileService.placeholder?(resolved_name)
    return unless Facebook::ContactProfileService.placeholder?(contact.name)

    contact.update!(name: resolved_name)
  end

  def schedule_name_refresh
    [15.seconds, 2.minutes].each do |wait|
      Facebook::RefreshContactNameJob.set(wait: wait).perform_later(@contact_inbox.id)
    end
  end

  def build_message
    return if response.identifier.present? && conversation.messages.exists?(source_id: response.identifier)

    @message = conversation.messages.create!(message_params)

    @attachments.each do |attachment|
      process_attachment(attachment)
    end
  end

  def conversation
    @conversation ||= set_conversation_based_on_inbox_config.tap { |found| reveal_on_desk(found) }
  end

  def reveal_on_desk(found)
    return if found.assignee_id.present?
    return unless found.pending?

    found.update!(status: :open, ai_assignee: nil)
  end

  def set_conversation_based_on_inbox_config
    if @inbox.lock_to_single_conversation
      Conversation.where(conversation_params).order(created_at: :desc).first || build_conversation
    else
      find_or_build_for_multiple_conversations
    end
  end

  def find_or_build_for_multiple_conversations
    # If lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    last_conversation = Conversation.where(conversation_params).where.not(status: :resolved).order(created_at: :desc).first
    return build_conversation if last_conversation.nil?

    last_conversation
  end

  def build_conversation
    Conversation.create!(conversation_params.merge(
                           contact_inbox_id: @contact_inbox.id
                         ))
  end

  def location_params(attachment)
    lat = attachment['payload']['coordinates']['lat']
    long = attachment['payload']['coordinates']['long']
    {
      external_url: attachment['url'],
      coordinates_lat: lat,
      coordinates_long: long,
      fallback_title: attachment['title']
    }
  end

  def fallback_params(attachment)
    {
      fallback_title: attachment['title'] || attachment.dig('payload', 'title'),
      external_url: attachment['url'] || attachment.dig('payload', 'url')
    }
  end

  # Facebook shared posts point to page URLs, not downloadable media URLs.
  # Both `share` and `post` attachment types carry a page URL rather than a media file,
  # so map them to `fallback` (which keeps the title/link without attempting a download).
  # Keep this Facebook-only so Messenger/Instagram share attachments still use the parent media handling.
  def normalize_file_type(type)
    return :fallback if [:share, :post].include?(type.to_sym)

    super
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact_inbox.contact_id
    }
  end

  def message_params
    content_attributes = {
      in_reply_to_external_id: response.in_reply_to_external_id
    }
    content_attributes[:external_echo] = true if @outgoing_echo

    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: @message_type,
      status: @outgoing_echo ? :delivered : :sent,
      content: response.content,
      source_id: response.identifier,
      content_attributes: content_attributes,
      sender: @outgoing_echo ? nil : @contact_inbox.contact
    }
  end

  def process_contact_params_result(result)
    name = Facebook::ContactProfileService.display_name(result) || Facebook::ContactProfileService::PLACEHOLDER_NAME

    {
      name: name,
      account_id: @inbox.account_id,
      avatar_url: result['profile_pic'] || result[:profile_pic]
    }
  end

  def contact_params
    result = Facebook::ContactProfileService.new(channel: @inbox.channel, sender_id: @sender_id).perform
    process_contact_params_result(result || {})
  rescue Koala::Facebook::AuthenticationError => e
    Rails.logger.warn("Facebook profile lookup failed for inbox #{@inbox.id}: #{e.message}")
    process_contact_params_result({})
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception unless e.is_a?(Koala::Facebook::ClientError) && @outgoing_echo
    process_contact_params_result({})
  end
end
