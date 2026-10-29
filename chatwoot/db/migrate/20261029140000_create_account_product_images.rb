class CreateAccountProductImages < ActiveRecord::Migration[7.1]
  def change
    add_column :account_product_sheets, :image_status, :string, null: false, default: 'none'
    add_column :account_product_sheets, :image_stats, :jsonb, null: false, default: {}

    create_table :account_product_images do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :product_sheet, null: false, foreign_key: { to_table: :account_product_sheets, on_delete: :cascade }
      t.integer :row_index, null: false
      t.string :source_digest, null: false
      t.string :content_hash
      t.string :status, null: false, default: 'completed'
      t.text :visual_summary
      t.jsonb :visual_attributes, null: false, default: {}
      t.string :failure_reason
      t.timestamps
    end

    add_index :account_product_images, [:account_id, :source_digest], name: 'index_account_product_images_on_account_and_source'
    add_index :account_product_images, [:account_id, :content_hash], name: 'index_account_product_images_on_account_and_content'
    add_index :account_product_images, [:product_sheet_id, :row_index], name: 'index_account_product_images_on_sheet_and_row'
  end
end
