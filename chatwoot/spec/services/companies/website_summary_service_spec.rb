require 'rails_helper'

RSpec.describe Companies::WebsiteSummaryService do
  let(:account) { create(:account) }
  let(:company) { create(:company, account: account, domain: 'acme.test', description: 'Widgets') }

  def html_page(body, about_href: nil)
    link = about_href ? "<a href=\"#{about_href}\">About</a>" : ''
    "<html><body>#{link}<p>#{body}</p><script>ignore()</script></body></html>"
  end

  it 'stores text from the homepage and a same-site about page' do
    stub_request(:get, 'https://acme.test')
      .to_return(status: 200, body: html_page('Home office hours', about_href: '/about'))
    stub_request(:get, 'https://acme.test/about')
      .to_return(status: 200, body: html_page('We repair widgets'))

    described_class.new(company).perform

    summary = company.reload.additional_attributes['website_summary']
    expect(summary).to include('Home office hours')
    expect(summary).to include('We repair widgets')
    expect(summary).not_to include('ignore()')
    expect(company.additional_attributes['website_summary_domain']).to eq('acme.test')
  end

  it 'does not follow a link on another site' do
    stub_request(:get, 'https://acme.test')
      .to_return(status: 200, body: html_page('Only home', about_href: 'https://other.test/about'))

    described_class.new(company).perform

    expect(company.reload.additional_attributes['website_summary']).to include('Only home')
    expect(a_request(:get, 'https://other.test/about')).not_to have_been_made
  end

  it 'clears a stored summary when the domain is removed' do
    company.update_columns(
      additional_attributes: { 'website_summary' => 'Old copy', 'website_summary_domain' => 'acme.test' }
    )
    company.update!(domain: nil)

    expect(company.reload.additional_attributes['website_summary']).to be_nil
  end
end
