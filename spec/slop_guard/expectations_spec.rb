# frozen_string_literal: true

RSpec.describe SlopGuard::Expectations do
  it 'uses named scenario identities independently of formatting' do
    parsed = described_class.new("## Expected behavior\n- [unique] Count one per visitor.\n## Failure cases\n- [nil] Reject nil.\n")
    expect(parsed.behaviors).to eq([{ 'id' => 'unique', 'text' => 'Count one per visitor.' }])
    expect(parsed.failures.first['id']).to eq('nil')
    expect(parsed.gaps).to eq([])
  end

  it 'makes missing and duplicate scenarios explicit' do
    expect(described_class.new('').gaps).to include('Missing expected behavior')
    expect(described_class.new("## Expected behavior\n- [same] One\n- [same] Two").gaps).to include('Duplicate scenario IDs')
  end
end
