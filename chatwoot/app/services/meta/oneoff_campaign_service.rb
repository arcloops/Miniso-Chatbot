class Meta::OneoffCampaignService
  pattr_initialize [:campaign!]

  BATCH_SIZE = 100

  def perform
    validate_campaign!
    Campaigns::SendMetaBatchJob.perform_later(campaign)
  end

  def perform_batch(cursor)
    contacts = audience_contacts.where('contacts.id > ?', cursor).order(:id).limit(BATCH_SIZE).to_a
    contacts.each { |contact| process_contact(contact) }
    contacts.last.id if contacts.size == BATCH_SIZE
  end

  # Used by a WhatsApp campaign so the same contact also receives the message
  # on Messenger and Instagram when those chats already exist.
  def deliver_social_channels(contact)
    social_inboxes.each { |target_inbox| deliver_on_inbox(contact, target_inbox) }
  end

  private

  delegate :inbox, to: :campaign

  def validate_campaign!
    raise "Invalid campaign #{campaign.id}" unless meta_campaign? && campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?
    raise 'Campaigns feature not enabled' unless campaign.account.feature_enabled?(:campaigns)
  end

  def meta_campaign?
    %w[Facebook Instagram].include?(inbox.inbox_type)
  end

  def audience_labels
    label_ids = Array(campaign.audience).select { |item| item['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: label_ids).pluck(:title)
  end

  def audience_contacts
    labels = audience_labels
    return campaign.account.contacts.none if labels.empty?

    from_contacts = campaign.account.contacts.tagged_with(labels, any: true).select(:id)
    from_conversations = inbox.conversations.tagged_with(labels, any: true).select(:contact_id)
    campaign.account.contacts.where(id: from_contacts).or(
      campaign.account.contacts.where(id: from_conversations)
    )
  end

  def process_contact(contact)
    social_inboxes.each { |target_inbox| deliver_on_inbox(contact, target_inbox) }
    whatsapp_inboxes.each { |target_inbox| deliver_on_inbox(contact, target_inbox) }
  end

  def social_inboxes
    @social_inboxes ||= campaign.account.inboxes.where(channel_type: %w[Channel::FacebookPage Channel::Instagram]).to_a
  end

  def whatsapp_inboxes
    @whatsapp_inboxes ||= campaign.account.inboxes.where(channel_type: 'Channel::Whatsapp').to_a
  end

  def deliver_on_inbox(contact, target_inbox)
    contact_inbox = contact.contact_inboxes.find_by(inbox_id: target_inbox.id)
    return log_skip(contact, "#{target_inbox.id} has no chat for this contact") if contact_inbox.blank?
    return log_skip(contact, "#{target_inbox.id} is missing a chat id") if contact_inbox.source_id.blank?

    conversation = contact_inbox.conversations.order(last_activity_at: :desc).first
    return log_skip(contact, "#{target_inbox.id} has no conversation") if conversation.blank?
    return log_skip(contact, "#{target_inbox.id} already sent") if already_sent?(conversation)
    return log_skip(contact, "#{target_inbox.id} is outside the reply window") unless Conversations::MessageWindowService.new(conversation).can_reply?

    content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
    return log_skip(contact, 'blank message') if content.blank?

    Messages::MessageBuilder.new(
      sender,
      conversation,
      ActionController::Parameters.new(content: content, campaign_id: campaign.id)
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Meta campaign #{campaign.id}] contact #{contact.id} inbox #{target_inbox.id} failed: #{e.class}")
  end

  def already_sent?(conversation)
    conversation.messages.outgoing.where(
      "additional_attributes->>'campaign_id' = ?", campaign.id.to_s
    ).exists?
  end

  def sender
    campaign.sender || campaign.account.administrators.first
  end

  def log_skip(contact, reason)
    Rails.logger.info("[Meta campaign #{campaign.id}] skipped contact #{contact.id}: #{reason}")
  end
end
