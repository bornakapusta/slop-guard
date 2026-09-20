# frozen_string_literal: true

RSpec.describe 'golden outputs' do
  it 'has a saved golden for every rendered output and nothing else' do
    expect(Goldens.saved).to eq(Goldens.all.keys.sort)
  end

  Goldens.all.each do |name, render|
    it "reproduces #{name} byte for byte" do
      expect(render.call).to eq(Goldens.read(name)),
                             "#{name} differs from spec/fixtures/golden. If the change is intended, run " \
                             'script/regenerate_goldens.rb and review the diff.'
    end
  end
end
