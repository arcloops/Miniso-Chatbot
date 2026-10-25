class AllowProductSheetHistory < ActiveRecord::Migration[7.1]
  def change
    remove_index :account_product_sheets, name: :index_account_product_sheets_on_account_id
    add_index :account_product_sheets, [:account_id, :created_at], name: :index_account_product_sheets_on_account_id_and_created_at
  end
end
