# frozen_string_literal: true

RSpec.describe SlopGuard::Report do
  it 'escapes mentions, links and HTML from untrusted evidence' do
    text = SlopGuard::Markdown.escape('<script> @everyone [link](http://example.com) `code`')
    expect(text).not_to include('<script>', '@everyone', '[link]')
    expect(text).to include('&lt;script&gt;')
  end

  it 'shows control characters and line separators as visible escapes so evidence cannot forge report structure' do
    text = SlopGuard::Markdown.escape("fixture\n## Injected\r- fake\e[31m\u2028tail")
    expect(text).to eq('fixture\n## Injected\r- fake\e\[31m\u2028tail')
    expect(text.lines.size).to eq(1)
    gap = "Missing fixture: spec/x\n## Forged heading"
    report = { 'status' => 'incomplete', 'snapshot' => 'abc',
               'rules' => { 'G1' => { 'outcome' => 'inconclusive', 'findings' => [], 'gaps' => [gap] } } }
    markdown = described_class.markdown(report)
    expect(markdown.lines.grep(/^## /).map(&:strip)).to eq(['## Slop Guard review'])
    expect(markdown).to include('Could not determine', 'Some checks could not reach a conclusion')
  end

  it 'keeps deliberate newlines but escapes other control characters in terminal messages' do
    message = SlopGuard.printable("Usage: x\n  --flag\e[2J", keep_newlines: true)
    expect(message).to eq("Usage: x\n  --flag\\e[2J")
  end
end

RSpec.describe 'findings from two rules at one location' do
  it 'renders each rule under its own heading so the JSON and Markdown finding sets agree' do
    finding = { 'scenario' => 'Reject nil', 'topic' => 'nil', 'anchor' => { 'path' => 'lib/input.rb', 'line' => 3 },
                'message' => 'The nil assertion is missing.', 'correction' => 'Assert the error.',
                'readings' => { 'missing' => 0.95 },
                'thresholds' => { 'high' => 0.85, 'low' => 0.2 } }
    report = { 'status' => 'complete', 'snapshot' => 'abc', 'rules' => %w[G1 G2].to_h do |id|
      [id, { 'outcome' => 'concern', 'findings' => [finding.merge('rule' => id)], 'gaps' => [] }]
    end }
    markdown = SlopGuard::Report.markdown(report)
    expect(markdown.scan('The nil assertion is missing.').size).to eq(2)
    expect(markdown.lines.grep(/^### /).map(&:strip)).to eq(['### Behavior test coverage', '### Failure case coverage'])
  end
end

RSpec.describe 'readable review results' do
  let(:report) do
    { 'status' => 'incomplete', 'snapshot' => 'abc',
      'rules' => { 'G1' => { 'outcome' => 'inconclusive', 'findings' => [],
                             'gaps' => ['Conflicting or uncertain coverage evidence: unchanged-count'] },
                   'G2' => { 'outcome' => 'no_concern', 'findings' => [], 'gaps' => [] },
                   'G4' => { 'outcome' => 'not_applicable', 'findings' => [], 'gaps' => [] } } }
  end

  it 'distinguishes unresolved checks from findings and puts internal diagnostics last' do
    markdown = SlopGuard::Report.markdown(report)
    visible, diagnostics = markdown.split('<details>', 2)
    expect(visible).to include('No actionable findings were reported.', 'This is not an all-clear.',
                               '| Behavior test coverage | Could not determine |',
                               '| Failure case coverage | No concern found |',
                               '| Unnecessary abstractions | Not applicable |',
                               "Could not establish whether tests prove requirement 'unchanged-count'",
                               'this does not establish that a test is missing')
    expect(visible).not_to include('Snapshot:', 'G1:', 'Conflicting or uncertain')
    expect(diagnostics).to include('Snapshot: `abc`', 'G1: inconclusive')
  end

  it 'distinguishes a failed review from an uncertain model judgment' do
    report['status'] = 'failed'
    expect(SlopGuard::Report.markdown(report)).to include('Review stopped before completion')
  end

  it 'does not hide unresolved checks when a rule also has a finding' do
    report['rules']['G1']['outcome'] = 'concern'
    expect(SlopGuard::Report.markdown(report)).to include('Needs attention; some checks unresolved')
  end

  it 'encodes filenames in source links and escapes the displayed label' do
    anchor = { 'path' => 'lib/a ](evil)#?.rb', 'line' => 3 }
    link = SlopGuard::Markdown.location(anchor, source_url: 'https://github.com/owner/demo/blob/abc')
    expect(link).to end_with('/lib/a%20%5D%28evil%29%23%3F%2Erb#L3)')
    expect(link).to start_with('[lib/a \\](evil)#?.rb:3](')
    expect(SlopGuard::Markdown.location(anchor)).not_to include('https://')
  end
end
