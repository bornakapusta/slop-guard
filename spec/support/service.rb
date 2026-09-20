# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/slop_guard/service'

RSpec.shared_context 'app service' do
  let(:directory) { Dir.mktmpdir('slop-guard-service') }
  let(:store) { SlopGuard::Service::Store.open(File.join(directory, 'app.sqlite3')) }
  let(:settings) do
    instance_double(SlopGuard::Service::Settings, repository: 'owner/demo', repository_id: 42,
                                                  installation_id: 7, app_id: 8, engine_revision: 'engine-v1',
                                                  webhook_secret: 's' * 32, data_dir: directory)
  end
  let(:client) { instance_double(SlopGuard::Service::GitHubClient, repo_path: '/repos/owner/demo', bot_login: 'guard[bot]') }
  let(:bot) { { 'login' => 'guard[bot]', 'type' => 'Bot' } }
  let(:head) { 'b' * 40 }
  let(:base) { 'a' * 40 }
  let(:pull) do
    { 'number' => 1, 'state' => 'open', 'draft' => false, 'body' => '', 'changed_files' => 1,
      'base' => { 'sha' => base, 'repo' => { 'id' => 42 } }, 'head' => { 'sha' => head } }
  end
  let(:finding) do
    { 'rule' => 'G4', 'topic' => 'ParserWrapper', 'scenario' => nil,
      'anchor' => { 'path' => 'lib/parser.rb', 'line' => 2 }, 'readings' => {}, 'thresholds' => {},
      'message' => 'Unnecessary abstraction', 'correction' => 'Keep the behavior in the existing parser.' }
  end
  let(:report) do
    { 'status' => 'complete', 'snapshot' => 'snapshot-1',
      'rules' => { 'G4' => { 'outcome' => 'concern', 'findings' => [finding], 'gaps' => [] } } }
  end
  let(:changed) { { 'lib/parser.rb' => [2] } }
  let(:reviews) { [] }
  let(:inline_comments) { [] }
  let(:summaries) { [] }

  before do
    allow(client).to receive(:list).with('/repos/owner/demo/pulls/1/reviews') { reviews }
    allow(client).to receive(:list).with('/repos/owner/demo/pulls/1/comments') { inline_comments }
    allow(client).to receive(:list).with('/repos/owner/demo/issues/1/comments') { summaries }
    allow(client).to receive(:post) do |path, data|
      object = { 'id' => 100 + reviews.size + summaries.size, 'body' => data[:body], 'user' => bot }
      path.end_with?('/reviews') ? reviews << object : summaries << object
      object
    end
    allow(client).to receive(:patch) { |_path, data| { 'body' => data[:body] } }
  end

  after do
    store.close
    FileUtils.remove_entry(directory)
  end
end
