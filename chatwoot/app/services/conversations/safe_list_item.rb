class Conversations::SafeListItem
  def self.collection(conversations)
    Array(conversations).filter_map { |conversation| dump(conversation) }
  end

  def self.dump(conversation)
    JSON.parse(
      ApplicationController.render(
        partial: 'api/v1/conversations/partials/conversation',
        formats: [:json],
        locals: { conversation: conversation }
      )
    )
  rescue StandardError => e
    Rails.logger.warn("Conversation #{conversation&.id} left out of the list: #{e.class}")
    nil
  end
end
