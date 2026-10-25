# == Schema Information
#
# Table name: account_product_sheets
#
#  id         :bigint           not null, primary key
#  filename   :string           not null
#  headers    :jsonb            not null
#  rows       :jsonb            not null
#  row_count  :integer          default(0), not null
#  truncated  :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_account_product_sheets_on_account_id_and_created_at  (account_id,created_at)
#
class AccountProductSheet < ApplicationRecord
  belongs_to :account

  validates :filename, presence: true

  scope :newest_first, -> { order(id: :desc) }
end
