require "test_helper"

class EntryReparseBatchJobTest < ActiveJob::TestCase
  setup do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
  end

  test "queues only a limited batch and schedules the next batch" do
    person = Person.create!(name: "Batch Person", birth_date: Date.new(2020, 1, 1))
    entries = 3.times.map do |index|
      person.entries.create!(input: "note #{index}", occurred_at: Time.current + index.minutes, parse_status: "pending", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })
    end

    assert_enqueued_jobs 3 do
      EntryReparseBatchJob.perform_now(batch_size: 2, max_pending: 2, delay_seconds: 15)
    end

    assert_equal 2, enqueued_jobs.count { |job| job[:job] == EntryDataParseJob }
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == EntryReparseBatchJob }
    assert_equal %w[pending pending pending], entries.map(&:reload).map(&:parse_status)
  end

  test "backs off when pending queue is already full" do
    person = Person.create!(name: "Pending Person", birth_date: Date.new(2020, 1, 1))
    person.entries.create!(input: "already pending", occurred_at: Time.current, parse_status: "pending", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })
    candidate = person.entries.create!(input: "candidate", occurred_at: Time.current, parse_status: "pending", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })

    EntryReparseBatchJob.class_eval do
      alias_method :__original_queued_parse_job_count_for_backoff_test, :queued_parse_job_count
      define_method(:queued_parse_job_count) { 1 }
    end

    begin
      assert_enqueued_jobs 1 do
        EntryReparseBatchJob.perform_now(batch_size: 5, max_pending: 1, delay_seconds: 12)
      end
    ensure
      EntryReparseBatchJob.class_eval do
        alias_method :queued_parse_job_count, :__original_queued_parse_job_count_for_backoff_test
        remove_method :__original_queued_parse_job_count_for_backoff_test
      end
    end

    assert_equal 0, enqueued_jobs.count { |job| job[:job] == EntryDataParseJob }
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == EntryReparseBatchJob }
    assert_equal "pending", candidate.reload.parse_status
  end

  test "counts outstanding parse jobs instead of pending entries" do
    person = Person.create!(name: "Queued Parse Person", birth_date: Date.new(2020, 1, 1))
    person.entries.create!(input: "queued", occurred_at: Time.current, parse_status: "pending", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })

    EntryReparseBatchJob.class_eval do
      alias_method :__original_queued_parse_job_count_for_test, :queued_parse_job_count
      define_method(:queued_parse_job_count) { 1 }
    end

    begin
      assert_enqueued_jobs 1 do
        EntryReparseBatchJob.perform_now(batch_size: 5, max_pending: 1, delay_seconds: 9)
      end
    ensure
      EntryReparseBatchJob.class_eval do
        alias_method :queued_parse_job_count, :__original_queued_parse_job_count_for_test
        remove_method :__original_queued_parse_job_count_for_test
      end
    end

    assert_equal 0, enqueued_jobs.count { |job| job[:job] == EntryDataParseJob }
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == EntryReparseBatchJob }
  end
end
