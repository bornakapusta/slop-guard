# frozen_string_literal: true

RSpec.describe SlopGuard::Report do
  it 'escapes mentions, links and HTML from untrusted evidence' do
    text = described_class.escape('<script> @everyone [link](http://example.com) `code`')
    expect(text).not_to include('<script>', '@everyone', '[link]')
    expect(text).to include('&lt;script&gt;')
  end
end

RSpec.describe 'shared test findings' do
  it 'renders one explanation with both guideline references while preserving machine attribution' do
    finding = { 'scenario' => 'Reject nil', 'topic' => 'nil', 'anchor' => { 'path' => 'lib/input.rb', 'line' => 3 },
                'message' => 'The nil assertion is missing.', 'correction' => 'Assert the error.',
                'readings' => { 'missing' => 0.95 },
                'thresholds' => { 'high' => 0.85, 'low' => 0.2 } }
    report = { 'status' => 'complete', 'snapshot' => 'abc', 'rules' => %w[G1 G2].to_h do |id|
      [id, { 'outcome' => 'concern', 'findings' => [finding.merge('rule' => id)], 'gaps' => [] }]
    end }
    markdown = SlopGuard::Report.markdown(report)
    expect(markdown.scan('The nil assertion is missing.').size).to eq(1)
    expect(markdown).to include('see G1; also applies to G2')
    expect(report['rules']['G2']['findings'].size).to eq(1)
  end
end
