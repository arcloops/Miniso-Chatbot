class Facebook::ResubscribePagesJob < ApplicationJob
  queue_as :low

  def perform
    Channel::FacebookPage.find_each do |page|
      page.subscribe
      page.reauthorized! if page.reauthorization_required?
    end
  end
end
