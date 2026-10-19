class Instagram::ResubscribeJob < ApplicationJob
  queue_as :low

  def perform
    Instagram::EnsureAppWebhookService.new.perform
    Channel::Instagram.find_each(&:subscribe)
  end
end
