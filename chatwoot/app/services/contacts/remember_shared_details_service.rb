class Contacts::RememberSharedDetailsService
  EMAIL_PATTERN = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i
  PHONE_PATTERN = /(?:\+|00)\d[\d\s().-]{6,16}\d/
  INSTAGRAM_PATTERN = %r{(?:https?://)?(?:www\.)?instagram\.com/([A-Za-z0-9._]{2,30})}i
  FACEBOOK_PATTERN = %r{(?:https?://)?(?:www\.)?(?:facebook|fb)\.com/(?!share|sharer|plugins|dialog)([A-Za-z0-9.\-]{3,})}i

  pattr_initialize [:contact!, :text!]

  def perform
    updates = {}
    updates[:email] = found_email if contact.email.blank? && found_email
    updates[:phone_number] = found_phone if contact.phone_number.blank? && found_phone
    profiles = shared_profiles
    if profiles.present?
      current = contact.additional_attributes || {}
      merged = (current['social_profiles'] || {}).merge(profiles)
      updates[:additional_attributes] = current.merge('social_profiles' => merged)
    end
    return if updates.blank?

    contact.update!(updates)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  private

  def found_email
    return @found_email if defined?(@found_email)

    candidate = text.to_s[EMAIL_PATTERN]&.downcase
    @found_email = candidate if candidate.present? && email_available?(candidate)
  end

  def found_phone
    return @found_phone if defined?(@found_phone)

    match = text.to_s[PHONE_PATTERN]
    @found_phone = normalize_phone(match)
  end

  def email_available?(email)
    !contact.account.contacts.where.not(id: contact.id).exists?(email: email)
  end

  def shared_profiles
    profiles = {}
    instagram = text.to_s[INSTAGRAM_PATTERN, 1]
    facebook = text.to_s[FACEBOOK_PATTERN, 1]
    current = contact.additional_attributes&.dig('social_profiles') || {}
    profiles['instagram'] = instagram if instagram.present? && current['instagram'].blank?
    facebook = nil if facebook.blank? || facebook.downcase.end_with?('.php')
    profiles['facebook'] = facebook if facebook.present? && current['facebook'].blank?
    profiles
  end

  def normalize_phone(raw)
    return if raw.blank?

    digits = raw.gsub(/[^\d+]/, '')
    digits = "+#{digits.delete_prefix('00')}" if digits.start_with?('00')
    digits = "+#{digits.delete_prefix('+')}" unless digits.start_with?('+')
    digits if digits.match?(/\A\+[1-9]\d{7,14}\z/)
  end
end