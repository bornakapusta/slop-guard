# frozen_string_literal: true

RSpec.describe SlopGuard::Report do
  it 'escapes mentions, links and HTML from untrusted evidence' do
    text = described_class.escape('<script> @everyone [link](http://example.com) `code`')
    expect(text).not_to include('<script>', '@everyone', '[link]')
    expect(text).to include('&lt;script&gt;')
  end

  it 'shows control characters and line separators as visible escapes so evidence cannot forge report structure' do
    text = described_class.escape("fixture\n## Injected\r- fake\e[31m\u2028tail")
    expect(text).to eq('fixture\n## Injected\r- fake\e\[31m\u2028tail')
    expect(text.lines.size).to eq(1)
    gap = "Missing fixture: spec/x\n## Forged heading"
    report = { 'status' => 'incomplete', 'snapshot' => 'abc',
               'rules' => { 'G1' => { 'outcome' => 'inconclusive', 'findings' => [], 'gaps' => [gap] } } }
    markdown = described_class.markdown(report)
    expect(markdown.lines.grep(/^## /).map(&:strip)).to eq(['## G1: inconclusive'])
  end

  it 'keeps deliberate newlines but escapes other control characters in terminal messages' do
    message = SlopGuard.printable("Usage: x\n  --flag\e[2J", keep_newlines: true)
    expect(message).to eq("Usage: x\n  --flag\\e[2J")
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
