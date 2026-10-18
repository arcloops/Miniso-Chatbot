# frozen_string_literal: true

class Facebook::ContactProfileService
  PROFILE_FIELDS = %w[name first_name last_name profile_pic].freeze
  PLACEHOLDER_NAME = 'John Doe'

  pattr_initialize [:channel!, :sender_id!]

  def perform
    api = Koala::Facebook::API.new(channel.page_access_token)
    result = api.get_object(sender_id, fields: PROFILE_FIELDS) || {}
    fill_name_from_conversation(api, result)
    result
  rescue Koala::Facebook::AuthenticationError
    raise
  rescue Koala::Facebook::ClientError => e
    # Profile lookups fail for some people even after they message the Page.
    # The conversation participant list still carries the name Facebook shows in the inbox.
    Rails.logger.warn(e) if e.message.include?('2018218')
    name = participant_name(api_or_new)
    name.present? ? { 'name' => name } : {}
  rescue StandardError => e
    Rails.logger.warn("Facebook profile lookup failed for page #{channel.page_id}: #{e.message}")
    name = participant_name(api_or_new)
    name.present? ? { 'name' => name } : {}
  end

  def self.placeholder?(name)
    name.blank? || name == PLACEHOLDER_NAME
  end

  def self.display_name(result)
    return if result.blank?

    result['name'].presence || result[:name].presence ||
      [result['first_name'] || result[:first_name], result['last_name'] || result[:last_name]].compact_blank.join(' ').presence
  end

  private

  def fill_name_from_conversation(api, result)
    return if self.class.display_name(result).present?

    name = participant_name(api)
    result['name'] = name if name.present?
  end

  def api_or_new
    Koala::Facebook::API.new(channel.page_access_token)
  end

  def participant_name(api)
    conversations = api.get_connections(
      channel.page_id,
      'conversations',
      { user_id: sender_id, fields: 'participants' }
    )
    participants = Array(conversations).flat_map { |conversation| participant_rows(conversation) }
    page_id = channel.page_id.to_s
    sender = sender_id.to_s
    match = participants.find { |person| field(person, 'id').to_s == sender && field(person, 'name').present? }
    match ||= participants.find { |person| field(person, 'id').to_s != page_id && field(person, 'name').present? }
    field(match, 'name')
  rescue StandardError => e
    Rails.logger.warn("Facebook conversation name lookup failed for page #{channel.page_id}: #{e.message}")
    nil
  end

  def participant_rows(conversation)
    data = conversation.dig('participants', 'data') || conversation.dig(:participants, :data)
    Array(data)
  end

  def field(record, key)
    return if record.blank?

    record[key] || record[key.to_sym]
  end
end
