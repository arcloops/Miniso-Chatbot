class Accounts::FetchWebsiteSummaryJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Accounts::WebsiteSummaryService.new(account).perform
  end
end
