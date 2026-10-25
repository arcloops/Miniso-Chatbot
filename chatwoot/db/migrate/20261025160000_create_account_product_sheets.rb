class CreateAccountProductSheets < ActiveRecord::Migration[7.1]
  def change
    create_table :account_product_sheets do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :filename, null: false
      t.jsonb :headers, null: false, default: []
      t.jsonb :rows, null: false, default: []
      t.integer :row_count, null: false, default: 0
      t.boolean :truncated, null: false, default: false
      t.timestamps
    end
  end
end
