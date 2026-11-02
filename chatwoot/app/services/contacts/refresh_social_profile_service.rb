class Contacts::RefreshSocialProfileService
  pattr_initialize [:contact!]

  def perform
    remember_channel_ids
    contact.contact_inboxes.includes(:conversations, inbox: :channel).find_each do |contact_inbox|
      channel = contact_inbox.inbox&.channel
      case channel
      when Channel::Instagram
        refresh_instagram(contact_inbox, channel)
      when Channel::FacebookPage
        if instagram_direct?(contact_inbox)
          refresh_instagram(contact_inbox, instagram_channel)
        else
          refresh_messenger(contact_inbox, channel)
        end
      end
    end
    remember_from_messages
  end

  private

  def refresh_instagram(contact_inbox, channel)
    return if channel.blank?
    return if recently_checked?('instagram') && instagram_handle.present?

    user = fetch_instagram_user(channel, contact_inbox.source_id)
    mark_checked('instagram')
    return if user.blank? || user['username'].blank?

    Instagram::WebhooksBaseService.apply_profile(inbox: contact_inbox.inbox, contact: contact, user: user)
  end

  def refresh_messenger(contact_inbox, channel)
    return if recently_checked?('messenger') && messenger_name.present?

    result = Facebook::ContactProfileService.new(channel: channel, sender_id: contact_inbox.source_id).perform
    mark_checked('messenger')
    return if result.blank?

    Facebook::ContactProfileService.remember_on_contact(contact, result)
    name = Facebook::ContactProfileService.display_name(result)
    contact.update!(name: name) if name.present? && Facebook::ContactProfileService.placeholder?(contact.name)
    avatar_url = result['profile_pic'] || result[:profile_pic]
    Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url) if avatar_url.present? && !contact.avatar.attached?
  rescue StandardError => e
    Rails.logger.warn("Messenger profile refresh skipped for contact #{contact.id}: #{e.class}")
    mark_checked('messenger')
  end

  def remember_channel_ids
    attrs = {}
    contact.contact_inboxes.includes(:conversations, inbox: :channel).find_each do |contact_inbox|
      source_id = contact_inbox.source_id.to_s.presence
      next if source_id.blank?

      case contact_inbox.inbox&.channel
      when Channel::Instagram
        attrs['social_instagram_user_id'] = source_id
      when Channel::FacebookPage
        if instagram_direct?(contact_inbox)
          attrs['social_instagram_user_id'] = source_id
        else
          attrs['social_messenger_user_id'] = source_id
        end
      when Channel::Whatsapp
        attrs['social_whatsapp_user_id'] = source_id
      end
    end
    return if attrs.blank?

    current = contact.additional_attributes || {}
    return if attrs.all? { |key, value| current[key] == value }

    contact.update!(additional_attributes: current.merge(attrs))
  end

  def remember_from_messages
    return if recently_checked?('shared_details')

    contact.messages.where(message_type: :incoming, private: false).order(id: :desc).limit(40).pluck(:content).each do |content|
      next if content.blank?

      Contacts::RememberSharedDetailsService.new(contact: contact, text: content).perform
    end
    mark_checked('shared_details')
  end

  def fetch_instagram_user(channel, ig_scope_id)
    return if channel.access_token.blank? || ig_scope_id.blank?

    fields = 'name,username,profile_pic,follower_count,is_user_follow_business,is_business_follow_user,is_verified_user'
    version = GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')
    response = HTTParty.get(
      "https://graph.instagram.com/#{version}/#{ig_scope_id}",
      query: { fields: fields, access_token: channel.access_token },
      timeout: 5
    )
    return unless response.success?

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.warn("Instagram profile refresh skipped for contact #{contact.id}: #{e.class}")
    nil
  end

  def instagram_direct?(contact_inbox)
    contact_inbox.conversations.any? do |conversation|
      conversation.additional_attributes.to_h['type'] == 'instagram_direct_message'
    end
  end

  def instagram_channel
    return @instagram_channel if defined?(@instagram_channel)

    inbox = contact.account.inboxes.includes(:channel).find { |item| item.channel.is_a?(Channel::Instagram) }
    @instagram_channel = inbox&.channel
  end

  def instagram_handle
    contact.additional_attributes['social_instagram_user_name'].presence ||
      contact.additional_attributes.dig('social_profiles', 'instagram')
  end

  def messenger_name
    contact.additional_attributes['social_messenger_first_name'].presence
  end

  def recently_checked?(channel_key)
    raw = contact.additional_attributes["#{channel_key}_profile_checked_at"]
    return false if raw.blank?

    Time.zone.parse(raw.to_s) > 12.hours.ago
  rescue ArgumentError, TypeError
    false
  end

  def mark_checked(channel_key)
    contact.update!(
      additional_attributes: (contact.additional_attributes || {}).merge(
        "#{channel_key}_profile_checked_at" => Time.current.iso8601
      )
    )
  end
end