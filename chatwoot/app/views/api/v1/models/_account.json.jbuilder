json.settings resource.settings
json.reporting_timezone ActiveSupport::TimeZone[resource.reporting_timezone].tzinfo.name if resource.reporting_timezone.present?
json.created_at resource.created_at
if resource.custom_attributes.present?
  json.custom_attributes do
    json.plan_name resource.custom_attributes['plan_name']
    json.subscribed_quantity resource.custom_attributes['subscribed_quantity']
    json.subscription_status resource.custom_attributes['subscription_status']
    json.subscription_ends_on resource.custom_attributes['subscription_ends_on']
    json.subscription_cancels_on resource.custom_attributes['subscription_cancels_on']
    json.billing_currency resource.billing_currency if resource.respond_to?(:billing_currency) && Enterprise::Billing::Currencies.enabled?
    json.website resource.custom_attributes['website'] if resource.custom_attributes['website'].present?
    json.bot_description resource.custom_attributes['bot_description'] if resource.custom_attributes['bot_description'].present?
    json.industry resource.custom_attributes['industry'] if resource.custom_attributes['industry'].present?
    json.company_size resource.custom_attributes['company_size'] if resource.custom_attributes['company_size'].present?
    json.timezone resource.custom_attributes['timezone'] if resource.custom_attributes['timezone'].present?
    json.logo resource.custom_attributes['logo'] if resource.custom_attributes['logo'].present?
    json.referral_source resource.custom_attributes['referral_source'] if resource.custom_attributes['referral_source'].present?
    json.brand_info resource.custom_attributes['brand_info'] if resource.custom_attributes['brand_info'].present?
    json.onboarding_step resource.onboarding_step if resource.onboarding_step.present?
    if resource.custom_attributes['help_center_generation_id'].present?
      json.help_center_generation_id resource.custom_attributes['help_center_generation_id']
    end
    json.marked_for_deletion_at resource.custom_attributes['marked_for_deletion_at'] if resource.custom_attributes['marked_for_deletion_at'].present?
    if resource.custom_attributes['marked_for_deletion_reason'].present?
      json.marked_for_deletion_reason resource.custom_attributes['marked_for_deletion_reason']
    end
  end
end
product_sheet = AccountProductSheet.where(account_id: resource.id).order(id: :desc).pick(:id, :filename, :row_count, :created_at, :truncated)
if product_sheet.present?
  json.product_sheet do
    json.id product_sheet[0]
    json.filename product_sheet[1]
    json.row_count product_sheet[2]
    json.updated_at product_sheet[3]
    json.truncated product_sheet[4]
  end
end
json.domain @account.domain
features = @account.enabled_features
features.delete(Shopify::FeatureGate::ACCOUNT_FEATURE) unless Shopify::FeatureGate.enabled?(account: @account)
json.features features
json.id @account.id
json.locale @account.locale
json.name @account.name
json.support_email @account.support_email
json.status @account.status
json.cache_keys @account.cache_keys
