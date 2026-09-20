# frozen_string_literal: true

require 'sqlite3'

module SlopGuard
  module Service
    # Durable inbox, paid-run checkpoints, and publication intents on one local disk.
    class Store
      SCHEMA = <<~SQL
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = FULL;
        CREATE TABLE IF NOT EXISTS identity (id INTEGER PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS deliveries (id TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS flags (id INTEGER PRIMARY KEY, enabled INTEGER NOT NULL);
        INSERT OR IGNORE INTO flags VALUES (1, 1);
        CREATE TABLE IF NOT EXISTS jobs (
          id INTEGER PRIMARY KEY, pr INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
          attempts INTEGER NOT NULL DEFAULT 0, available_at INTEGER NOT NULL DEFAULT 0, error TEXT
        );
        CREATE TABLE IF NOT EXISTS runs (
          id TEXT PRIMARY KEY, pr INTEGER NOT NULL, phase TEXT NOT NULL, report TEXT, changed TEXT
        );
        CREATE TABLE IF NOT EXISTS publications (
          id TEXT PRIMARY KEY, remote_id INTEGER, attempted INTEGER NOT NULL DEFAULT 0
        );
      SQL

      # Opens or creates the database, applies the schema and, when an identity is given, binds the data
      # directory to it. There is no other way to obtain a Store.
      def self.open(path, identity: nil)
        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        db.busy_timeout = 2000
        db.execute_batch(SCHEMA)
        bind(db, identity) if identity
        new(db)
      end

      def self.bind(db, identity)
        value = JSON.generate(identity)
        db.execute('INSERT OR IGNORE INTO identity VALUES (1, ?)', [value])
        return if db.execute('SELECT value FROM identity WHERE id = 1').first['value'] == value

        db.close
        raise InvalidInput, 'This data directory belongs to another GitHub App installation or repository'
      end
      private_class_method :new, :bind

      def initialize(db)
        @mutex = Mutex.new
        @db = db
      end

      def health?
        query('SELECT 1').any?
      end

      def close
        @db.close
      end

      def receive(delivery, number: nil, enabled: nil)
        @mutex.synchronize do
          @db.transaction(:immediate) do
            @db.execute('INSERT OR IGNORE INTO deliveries VALUES (?)', [delivery])
            if @db.changes.zero?
              :duplicate
            else
              @db.execute('UPDATE flags SET enabled = ? WHERE id = 1', [enabled ? 1 : 0]) unless enabled.nil?
              @db.execute('INSERT INTO jobs (pr) VALUES (?)', [number]) if number
              :accepted
            end
          end
        end
      end

      def enabled?
        query('SELECT enabled FROM flags WHERE id = 1').first.fetch('enabled') == 1
      end

      def recover
        query("UPDATE jobs SET state = 'pending' WHERE state = 'processing'")
      end

      def claim
        @mutex.synchronize do
          @db.transaction(:immediate) do
            @db.execute("UPDATE jobs SET state = 'superseded' WHERE state = 'pending' AND " \
                        'id NOT IN (SELECT MAX(id) FROM jobs GROUP BY pr)')
            sql = "SELECT * FROM jobs WHERE state = 'pending' AND available_at <= ? ORDER BY id LIMIT 1"
            row = @db.get_first_row(sql, [Time.now.to_i])
            if row
              @db.execute("UPDATE jobs SET state = 'processing', attempts = attempts + 1 WHERE id = ?", [row['id']])
              row['attempts'] += 1
            end
            row
          end
        end
      end

      def current?(job)
        enabled? && query('SELECT MAX(id) AS id FROM jobs WHERE pr = ?', job.fetch('pr')).first['id'] == job['id']
      end

      def finish(job, state, error: nil, delay: 0)
        query('UPDATE jobs SET state = ?, error = ?, available_at = ? WHERE id = ?',
              state, error, Time.now.to_i + delay, job.fetch('id'))
      end

      def run(id)
        query('SELECT * FROM runs WHERE id = ?', id).first
      end

      def begin_run(id, number)
        query("INSERT INTO runs (id, pr, phase) VALUES (?, ?, 'prepared')", id, number)
      end

      def evaluating(id)
        query("UPDATE runs SET phase = 'evaluating' WHERE id = ?", id)
      end

      def save_run(id, report, changed)
        query("UPDATE runs SET phase = 'evaluated', report = ?, changed = ? WHERE id = ?",
              JSON.generate(report), JSON.generate(changed), id)
      end

      def published(id)
        query("UPDATE runs SET phase = 'published' WHERE id = ?", id)
      end

      def previous_complete(number, excluding:)
        rows = query('SELECT report FROM runs WHERE pr = ? AND id != ? AND report IS NOT NULL ORDER BY rowid DESC',
                     number, excluding)
        rows.map { |row| JSON.parse(row['report']) }.find { |report| report['status'] == 'complete' }
      end

      def publication(id)
        query('SELECT * FROM publications WHERE id = ?', id).first
      end

      def intend(id)
        query('INSERT INTO publications (id, attempted) VALUES (?, 1) ' \
              'ON CONFLICT(id) DO UPDATE SET attempted = 1', id)
      end

      def clear_intent(id)
        query('DELETE FROM publications WHERE id = ? AND remote_id IS NULL', id)
      end

      def confirmed(id, remote_id)
        query('INSERT INTO publications (id, remote_id) VALUES (?, ?) ' \
              'ON CONFLICT(id) DO UPDATE SET remote_id = excluded.remote_id', id, remote_id)
      end

      private

      def query(sql, *values)
        @mutex.synchronize { @db.execute(sql, values) }
      end
    end
  end
end
