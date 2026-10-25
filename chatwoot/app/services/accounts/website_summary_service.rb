class Accounts::WebsiteSummaryService
  def initialize(account)
    @account = account
  end

  def perform
    website = @account.bot_website
    return clear_summary if website.blank?

    summary = WebsitePageFetcher.summary_for(website)
    if summary.blank?
      clear_summary if stored_domain != website
      return
    end

    store_summary(summary, website)
  end

  private

  def stored_domain
    @account.internal_attributes['bot_website_summary_domain']
  end

  def store_summary(summary, website)
    attributes = (@account.internal_attributes || {}).merge(
      'bot_website_summary' => summary,
      'bot_website_summary_domain' => website
    )
    @account.update_columns(internal_attributes: attributes, updated_at: Time.current)
  end

  def clear_summary
    return if @account.internal_attributes.blank?
    return if @account.internal_attributes['bot_website_summary'].blank? && stored_domain.blank?

    attributes = @account.internal_attributes.except('bot_website_summary', 'bot_website_summary_domain')
    @account.update_columns(internal_attributes: attributes, updated_at: Time.current)
  end
end
