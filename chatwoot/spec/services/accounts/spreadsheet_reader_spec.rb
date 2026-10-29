require 'rails_helper'

RSpec.describe Accounts::SpreadsheetReader do
  it 'reads product rows from a csv' do
    parsed = described_class.read('stock.csv', "Product,Price,Stock\nBlue pen,80,12\n")

    expect(parsed[:headers]).to eq(['Product', 'Price', 'Stock'])
    expect(parsed[:rows]).to eq([['Blue pen', '80', '12']])
    expect(parsed[:truncated]).to be(false)
  end

  it 'keeps an image link instead of cutting it off' do
    url = "https://cdn.example.com/products/#{'blue-pen-' * 8}photo.jpg"
    parsed = described_class.read('stock.csv', "Product,Price,Image\nBlue pen,80,#{url}\n")

    expect(parsed[:rows].first.last).to eq(url)
  end

  it 'reads an image placed in the csv instead of treating it as text' do
    png = Base64.strict_encode64("\x89PNG\r\n\x1A\n#{"\x00" * 16}".b)
    csv = CSV.generate do |sheet|
      sheet << %w[Product Price Image]
      sheet << ['Blue pen', '80', "data:image/png;base64,#{png}"]
    end
    parsed = described_class.read('stock.csv', csv)

    expect(parsed[:rows].first).to eq(['Blue pen', '80', ''])
    expect(parsed[:images].first[:content_type]).to eq('image/png')
    expect(parsed[:images].first[:row_index]).to eq(0)
  end

  it 'keeps a picture on the product row when a blank row sits above it' do
    png = Base64.strict_encode64("\x89PNG\r\n\x1A\n#{"\x00" * 16}".b)
    csv = CSV.generate do |sheet|
      sheet << %w[Product Price Image]
      sheet << ['Blue pen', '80', nil]
      sheet << [nil, nil, nil]
      sheet << ['Red cup', '40', "data:image/png;base64,#{png}"]
      sheet << ['Green mug', '20', nil]
    end
    parsed = described_class.read('stock.csv', csv)

    expect(parsed[:rows].map(&:first)).to eq(['Blue pen', 'Red cup', 'Green mug'])
    expect(parsed[:images].first[:row_index]).to eq(1)
  end

  it 'rejects a file that is not a csv or xlsx' do
    expect { described_class.read('stock.xls', 'old') }.to raise_error(described_class::Error, /csv or \.xlsx/)
  end
end
