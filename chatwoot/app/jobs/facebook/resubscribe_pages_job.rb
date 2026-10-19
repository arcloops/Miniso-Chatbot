class Facebook::ResubscribePagesJob < ApplicationJob
  queue_as :low

  def perform
    Facebook::RegisterWebhooksService.new.perform
    Channel::FacebookPage.find_each do |page|
      page.subscribe
      page.reauthorized! if page.reauthorization_required?
    end
    reveal_messenger_threads
  end

  private

  def reveal_messenger_threads
    Conversation.joins(:inbox)
                .where(inboxes: { channel_type: 'Channel::FacebookPage' }, status: :pending, assignee_id: nil)
                .update_all(status: Conversation.statuses[:open], updated_at: Time.current)
  end
end
