# frozen_string_literal: true

class Facebook::RefreshContactNameJob < ApplicationJob
  queue_as :low
  self.enqueue_after_transaction_commit = true

  def perform(contact_inbox_id)
    contact_inbox = ContactInbox.find_by(id: contact_inbox_id)
    return if contact_inbox.blank?

    contact = contact_inbox.contact
    return unless Facebook::ContactProfileService.placeholder?(contact.name)

    channel = contact_inbox.inbox&.channel
    return unless channel.is_a?(Channel::FacebookPage)

    result = Facebook::ContactProfileService.new(channel: channel, sender_id: contact_inbox.source_id).perform
    name = Facebook::ContactProfileService.display_name(result)
    return if Facebook::ContactProfileService.placeholder?(name)

    contact.update!(name: name)
    avatar_url = result['profile_pic'] || result[:profile_pic]
    ::Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url) if avatar_url.present? && !contact.avatar.attached?
  rescue Koala::Facebook::AuthenticationError => e
    ContactInbox.find_by(id: contact_inbox_id)&.inbox&.channel&.authorization_error!
    Rails.logger.warn("Facebook name refresh unauthorized for contact inbox #{contact_inbox_id}: #{e.message}")
  end
end
