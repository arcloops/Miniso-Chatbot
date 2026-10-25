class Companies::WebsiteSummaryService
  def initialize(company)
    @company = company
  end

  def perform
    return clear_summary if @company.domain.blank?

    summary = WebsitePageFetcher.summary_for(@company.domain)
    if summary.blank?
      clear_summary if stored_domain != @company.domain
      return
    end

    store_summary(summary)
  end

  private

  def stored_domain
    @company.additional_attributes['website_summary_domain']
  end

  def store_summary(summary)
    attributes = (@company.additional_attributes || {}).merge(
      'website_summary' => summary,
      'website_summary_domain' => @company.domain
    )
    @company.update_columns(additional_attributes: attributes, updated_at: Time.current)
  end

  def clear_summary
    return if @company.additional_attributes.blank?
    return if @company.additional_attributes['website_summary'].blank? && stored_domain.blank?

    attributes = @company.additional_attributes.except('website_summary', 'website_summary_domain')
    @company.update_columns(additional_attributes: attributes, updated_at: Time.current)
  end
end
