class Instagram::WebhooksBaseService
  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  def self.apply_profile(inbox:, contact:, user:)
    service = new(inbox.channel)
    service.instance_variable_set(:@inbox, inbox)
    service.instance_variable_set(:@contact, contact)
    service.send(:apply_instagram_contact_name, user)
    service.send(:update_instagram_profile_link, user)
    Avatar::AvatarFromUrlJob.perform_later(contact, user['profile_pic']) if user['profile_pic'].present? && !contact.avatar.attached?
  end

  private

  def inbox_channel(_instagram_id)
    @inbox = ::Inbox.find_by(channel: @channel)
  end

  def find_or_create_contact(user)
    @contact_inbox = @inbox.contact_inboxes.where(source_id: user['id']).first
    @contact = @contact_inbox.contact if @contact_inbox

    if @contact
      apply_instagram_contact_name(user)
      update_instagram_profile_link(user)
      return
    end

    @contact_inbox = @inbox.channel.create_contact_inbox(
      user['id'], instagram_contact_name(user)
    )

    @contact = @contact_inbox.contact
    update_instagram_profile_link(user)
    Avatar::AvatarFromUrlJob.perform_later(@contact, user['profile_pic']) if user['profile_pic']
  end

  # Instagram's profile "name" is sometimes a generated string such as quiet-smoke-724.
  # The username is the handle people recognize, so that is what the desk shows.
  def instagram_contact_name(user)
    username = user['username'].to_s.strip.presence
    raw_name = user['name'].to_s.strip.presence
    return username if raw_name.blank? || (username.present? && generated_instagram_name?(raw_name))

    raw_name || username
  end

  def apply_instagram_contact_name(user)
    corrected = instagram_contact_name(user)
    return if corrected.blank?
    return unless @contact.name.blank? || generated_instagram_name?(@contact.name)

    @contact.update!(name: corrected)
  end

  def generated_instagram_name?(name)
    name.to_s.match?(/\A[a-z]+(?:-[a-z]+){1,3}-\d+\z/)
  end

  def update_instagram_profile_link(user)
    instagram_attributes = build_instagram_attributes(user)
    return if instagram_attributes.blank?

    @contact.update!(additional_attributes: @contact.additional_attributes.merge(instagram_attributes))
  end

  def build_instagram_attributes(user)
    attributes = {}
    username = user['username'].to_s.strip.presence
    if username
      current = @contact.additional_attributes || {}
      profiles = (current['social_profiles'] || {}).merge('instagram' => username)
      attributes['social_profiles'] = profiles
      attributes['social_instagram_user_name'] = username
    end

    # Add optional attributes if present
    optional_fields = %w[
      follower_count
      is_user_follow_business
      is_business_follow_user
      is_verified_user
    ]

    optional_fields.each do |field|
      next if user[field].nil?

      attributes["social_instagram_#{field}"] = user[field]
    end

    attributes
  end
end
