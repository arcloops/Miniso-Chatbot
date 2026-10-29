# == Schema Information
#
# Table name: account_product_images
#
#  id                 :bigint           not null, primary key
#  content_hash       :string
#  failure_reason     :string
#  row_index          :integer          not null
#  source_digest      :string           not null
#  status             :string           default("completed"), not null
#  visual_attributes  :jsonb            not null
#  visual_summary     :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  product_sheet_id   :bigint           not null
#
class AccountProductImage < ApplicationRecord
  belongs_to :account
  belongs_to :product_sheet, class_name: 'AccountProductSheet'

  scope :readable, -> { where(status: 'completed').where.not(visual_summary: [nil, '']) }
end
