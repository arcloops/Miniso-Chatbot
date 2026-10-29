require 'rails_helper'

RSpec.describe Accounts::SafeImageFetch do
  it 'rejects a private address' do
    expect(described_class.public_ip?('127.0.0.1')).to be(false)
    expect(described_class.public_ip?('10.1.1.1')).to be(false)
    expect(described_class.public_ip?('192.168.0.8')).to be(false)
  end

  it 'accepts a public address' do
    expect(described_class.public_ip?('8.8.8.8')).to be(true)
  end
end

RSpec.describe Accounts::ProductSheetService do
  let(:account) { create(:account) }
  let(:sheet) do
    account.product_sheets.create!(
      filename: 'stock.csv',
      headers: ['Product', 'Price', 'Stock'],
      rows: [['Blue pen', '80', '12'], ['Red cup', '40', '3']],
      row_count: 2
    )
  end

  it 'uses the catalog price when the photo description matches one product' do
    sheet.product_images.create!(
      account: account,
      row_index: 0,
      source_digest: 'abc',
      status: 'completed',
      visual_summary: 'matte blue pen bottle'
    )

    text = described_class.reply_text(account, 'how much is this', image_note: 'matte blue pen bottle')

    expect(text).to include('Confirmed catalog row')
    expect(text).to include('80')
    expect(text).not_to include('40')
  end

  it 'does not give a price when the photo matches more than one product' do
    sheet.product_images.create!(
      account: account, row_index: 0, source_digest: 'abc', status: 'completed', visual_summary: 'matte blue pen bottle'
    )
    sheet.product_images.create!(
      account: account, row_index: 1, source_digest: 'def', status: 'completed', visual_summary: 'matte blue pen bottle cup'
    )

    text = described_class.reply_text(account, 'how much is this', image_note: 'matte blue pen bottle')

    expect(text).to include('Ask which one')
    expect(text).to include('before giving a price')
  end

  it 'does not invent a price when the photo matches nothing' do
    sheet.product_images.create!(
      account: account, row_index: 0, source_digest: 'abc', status: 'completed', visual_summary: 'matte blue pen bottle'
    )

    text = described_class.reply_text(account, 'what is this', image_note: 'ceramic cactus vase')

    expect(text).to include('did not match')
    expect(text).not_to include('80')
  end
end

RSpec.describe Accounts::CatalogImageIndexer do
  let(:account) { create(:account) }
  let(:url) { 'https://cdn.example.com/blue-pen.jpg' }

  it 'reuses a picture that was already described' do
    digest = Digest::SHA256.hexdigest(url)
    first = account.product_sheets.create!(
      filename: 'old.csv',
      headers: ['Product', 'Image'],
      rows: [['Blue pen', url]],
      row_count: 1
    )
    first.product_images.create!(
      account: account,
      row_index: 0,
      source_digest: digest,
      content_hash: 'same-bytes',
      status: 'completed',
      visual_summary: 'matte blue pen bottle'
    )
    sheet = account.product_sheets.create!(
      filename: 'new.csv',
      headers: ['Product', 'Image'],
      rows: [['Blue pen', url]],
      row_count: 1
    )
    expect(Accounts::SafeImageFetch).not_to receive(:fetch)

    described_class.new(sheet.id).perform

    expect(sheet.reload.image_stats['reused']).to eq(1)
    expect(sheet.image_stats['indexed']).to eq(0)
    expect(sheet.product_images.last.visual_summary).to eq('matte blue pen bottle')
  end

  it 'keeps the product rows when a picture cannot be fetched' do
    sheet = account.product_sheets.create!(
      filename: 'new.csv',
      headers: ['Product', 'Price', 'Image'],
      rows: [['Blue pen', '80', url]],
      row_count: 1
    )
    allow(Accounts::SafeImageFetch).to receive(:fetch).and_return(nil)

    described_class.new(sheet.id).perform

    expect(sheet.reload.rows.first).to include('80')
    expect(sheet.image_status).to eq('failed')
    expect(sheet.image_stats['failed']).to eq(1)
  end
end
