# frozen_string_literal: true

# Literal digests pinned on 2026-09-20. Every one is SHA-256 over JSON.generate, so hash key ORDER is part of the
# value. A refactor that changes any of these has changed a published identity, not just internal structure.
RSpec.describe 'pinned digests' do
  it 'keeps both saved rule revisions' do
    expect(SlopGuard::Rules.load(demo_profile.rules_dir).revision)
      .to eq('89dea7e917d39f79a861e1b39606e8c77109bc3993e6c9328d3cb5fe67ce7e6a')
    expect(SlopGuard::Rules.load(ruby_profile.rules_dir).revision)
      .to eq('b7f212799e6fdb406252defbc4285e994f118d5734209d4cbb2692717b1d950d')
  end

  it 'keeps the g1-violation snapshot identity' do
    expect(Goldens.snapshot.identity).to eq('76defbd8de0c63f49c89caa8b4be7c305242e9443203a277f3cabba4d1c7df11')
  end

  it 'fingerprints exactly the state and typed questions handed to the provider, in ask order' do
    client = Goldens.fixed_client
    report = Goldens.review(client: client)
    fingerprints = report['rules'].values.flat_map { |rule| rule['question_fingerprints'] }
    expect(fingerprints).to eq(client.asks.map { |state, typed| SlopGuard.digest([state, typed]) })
    expect(fingerprints.first).to eq('53564826be677568ea010b12238d2c93584e59d86fda53b3159ab398c89a7715')
    expect(report.dig('rules', 'G1', 'findings', 0, 'id'))
      .to eq('43711cdf1ab3670bc58d7bf9f2cdc8f86c19cdd7240c5acbb547959483ca3a7b')
  end

  it 'builds the in-memory report from String keys only, so scoring and rendering read the same keys as JSON' do
    keys = []
    walk = lambda do |value|
      case value
      when Hash
        value.each do |key, child|
          keys << key
          walk.call(child)
        end
      when Array then value.each(&walk)
      end
    end
    walk.call(Goldens.review(fail_design: true))
    expect(keys.grep_v(String)).to be_empty
  end

  it 'adds the error key to a rule result only when a provider failure was recorded' do
    report = Goldens.review(fail_design: true)
    expect(report.dig('rules', 'G1')).not_to have_key('error')
    expect(report.dig('rules', 'G2').keys).to eq(%w[outcome findings gaps readings question_fingerprints error])
  end
end
