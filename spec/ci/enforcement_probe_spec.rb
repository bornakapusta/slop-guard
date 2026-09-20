# frozen_string_literal: true

RSpec.describe 'Temporary merge-enforcement probe' do
  it 'fails deliberately to verify the required Tests check' do
    expect(true).to be(false)
  end
end
