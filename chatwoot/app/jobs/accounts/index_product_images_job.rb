class Accounts::IndexProductImagesJob < ApplicationJob
  queue_as :default

  def perform(sheet_id)
    Accounts::CatalogImageIndexer.new(sheet_id).perform
  end
end
