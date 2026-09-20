# frozen_string_literal: true

require_relative '../../support/service'

RSpec.describe SlopGuard::Service::Publisher do
  include_context 'app service'
  let(:publisher) { described_class.new(client: client, store: store) }
  let(:current) { -> {} }

  def publish(id = 'run-1', result = report, lines = changed)
    publisher.publish(number: 1, head: head, run_id: id, report: result, changed: lines, current: current)
  end

  it 'posts an advisory review pinned to the commit with changed-line anchors and a summary' do
    publish
    comment = hash_including(path: 'lib/parser.rb', line: 2, side: 'RIGHT')
    expected = hash_including(commit_id: head, event: 'COMMENT', comments: [comment])
    expect(client).to have_received(:post).with('/repos/owner/demo/pulls/1/reviews', expected)
    expect(summaries.first['body']).to include('Unnecessary abstraction', head)
  end

  it 'leaves findings with invalid or deleted anchors only in the summary' do
    publish('run-1', report, { 'lib/parser.rb' => [] })
    expect(reviews).to be_empty
    expect(summaries.first['body']).to include('Unnecessary abstraction')
  end

  it 'caps inline noise while retaining all findings in the summary' do
    report['rules']['G4']['findings'] = (1..25).map { |i| finding.merge('topic' => "Wrapper#{i}") }
    publish
    expect(client).to have_received(:post).with('/repos/owner/demo/pulls/1/reviews',
                                                hash_including(comments: an_instance_of(Array))) do |_path, data|
      expect(data[:comments].length).to eq(20)
    end
    expect(summaries.first['body']).to include('Wrapper25')
  end

  it 'reconciles a lost create response without sending another review' do
    calls = 0
    allow(client).to receive(:post).with('/repos/owner/demo/pulls/1/reviews', anything) do |_path, data|
      calls += 1
      reviews << { 'id' => 200, 'body' => data[:body], 'user' => bot }
      raise SlopGuard::Service::GitHubClient::Failure
    end
    expect { publish }.to raise_error(SlopGuard::Service::GitHubClient::Failure)
    publish
    expect(calls).to eq(1)
    expect(summaries.length).to eq(1)
  end

  it 'does not repeat a create whose outcome cannot be determined' do
    store.intend('review:run-1')
    expect { publish }.to raise_error(SlopGuard::Service::PublicationUncertain)
    expect(client).not_to have_received(:post)
  end

  it 'updates the single summary on redelivery' do
    publish
    publish
    expect(reviews.length).to eq(1)
    expect(summaries.length).to eq(1)
    expect(client).to have_received(:patch).with('/repos/owner/demo/issues/comments/101', anything)
  end

  it 'reuses a matching inline thread that GitHub still maps to the changed line' do
    publish
    body = nil
    expect(client).to have_received(:post).with('/repos/owner/demo/pulls/1/reviews', anything) do |_path, data|
      body = data[:comments].first[:body]
    end
    inline_comments << { 'id' => 300, 'user' => bot, 'path' => 'lib/parser.rb', 'line' => 2,
                         'position' => 2, 'body' => body }
    publish('run-2')
    expect(reviews.length).to eq(1)
    expect(client).to have_received(:patch).with('/repos/owner/demo/pulls/comments/300', anything)
  end

  it 'never edits a human comment containing a forged bot marker' do
    summaries << { 'id' => 10, 'user' => { 'login' => 'human', 'type' => 'User' },
                   'body' => described_class::SUMMARY_MARKER }
    publish
    expect(summaries.length).to eq(2)
    expect(client).not_to have_received(:patch).with('/repos/owner/demo/issues/comments/10', anything)
  end

  it 'falls back to the summary if GitHub rejects inline locations' do
    allow(client).to receive(:post).with('/repos/owner/demo/pulls/1/reviews', anything)
                                   .and_raise(SlopGuard::Service::GitHubClient::Failure.new(422))
    publish
    expect(summaries.first['body']).to include('GitHub rejected inline locations', 'Unnecessary abstraction')
    publish
    expect(client).to have_received(:post).with('/repos/owner/demo/pulls/1/reviews', anything).once
  end

  it 'stops publication when the PR changes' do
    allow(current).to receive(:call).and_raise(SlopGuard::Service::StaleReview)
    expect { publish }.to raise_error(SlopGuard::Service::StaleReview)
    expect(client).not_to have_received(:post)
  end

  it 'preserves the previous complete report when a new review is incomplete' do
    store.begin_run('old', 1)
    store.save_run('old', report, changed)
    result = { 'status' => 'incomplete', 'snapshot' => 'new',
               'rules' => { 'G4' => { 'outcome' => 'inconclusive', 'findings' => [],
                                      'gaps' => ['Missing evidence'] } } }
    publish('new', result)
    expect(summaries.first['body']).to include('not cleared', 'Missing evidence', 'Unnecessary abstraction')
  end
end
