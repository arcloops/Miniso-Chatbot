class Companies::FetchWebsiteSummaryJob < ApplicationJob
  queue_as :low

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return if company.blank?

    Companies::WebsiteSummaryService.new(company).perform
  end
end
