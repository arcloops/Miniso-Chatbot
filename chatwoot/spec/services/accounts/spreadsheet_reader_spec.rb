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

  it 'rejects a file that is not a csv or xlsx' do
    expect { described_class.read('stock.xls', 'old') }.to raise_error(described_class::Error, /csv or \.xlsx/)
  end
end
