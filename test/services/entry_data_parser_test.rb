require "test_helper"

class EntryDataParserTest < ActiveSupport::TestCase
  test "falls back to extracted document text when multimodal request fails" do
    person = Person.create!(name: "Parser Fallback", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(input: "seed", occurred_at: Time.current, facts: [], parseable_data: [], parse_status: "pending")
    entry.documents.attach(io: StringIO.new("Ibuprofen 400mg invoice"), filename: "invoice.txt", content_type: "text/plain")

    preference = AppSetting.current
    preference.llm_api_key = "test-key"
    preference.llm_provider = "openrouter"
    preference.llm_model = "openai/gpt-5.4"
    preference.save!

    multimodal_singleton = LlmMultimodalRequest.singleton_class
    chat_singleton = LlmChatRequest.singleton_class

    multimodal_singleton.alias_method :__original_multimodal_call_for_fallback_test, :call
    chat_singleton.alias_method :__original_chat_call_for_fallback_test, :call

    captured_message = nil

    multimodal_singleton.define_method(:call) { |**| raise StandardError, "multimodal failed" }
    chat_singleton.define_method(:call) do |**kwargs|
      captured_message = kwargs[:messages].last[:content]

      LlmChatRequest::Response.new(
        content: { facts: [ "Medication ibuprofen 400 mg" ], parseable_data: [ { type: "medication", value: "ibuprofen", dose: "400mg" } ], occurred_at: nil, llm_response: { status: "structured", confidence: "medium", note: "Fallback text extraction used." } }.to_json,
        status_code: 200,
        body: "{}"
      )
    end

    result = EntryDataParser.call(input: "", preference:, entry: entry)

    assert_includes captured_message, "Ibuprofen 400mg invoice"
    assert_equal [ "Medication ibuprofen 400 mg" ], result.fact_texts
    assert_equal "medication", result.parseable_data.first["type"]
  ensure
    if multimodal_singleton.method_defined?(:__original_multimodal_call_for_fallback_test)
      multimodal_singleton.alias_method :call, :__original_multimodal_call_for_fallback_test
      multimodal_singleton.remove_method :__original_multimodal_call_for_fallback_test
    end
    if chat_singleton.method_defined?(:__original_chat_call_for_fallback_test)
      chat_singleton.alias_method :call, :__original_chat_call_for_fallback_test
      chat_singleton.remove_method :__original_chat_call_for_fallback_test
    end
  end

  test "sanitizes lab result items" do
    payload = [
      { "type" => "lab_result", "value" => "Hemoglobin", "result" => "15.2", "unit" => "g/dl", "ref" => "13.5-17.5" }
    ]

    result = EntryDataParser.sanitize_parseable_data(payload)

    assert_equal "lab_result", result.first["type"]
    assert_equal "Hemoglobin", result.first["value"]
    assert_equal 15.2, result.first["result"]
    assert_equal "g/dl", result.first["unit"]
    assert_equal "13.5-17.5", result.first["ref"]
  end

  test "user prompt includes source metadata for healthkit entries" do
    person = Person.create!(name: "Prompt Source", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(
      input: "Apple Health monthly summary",
      occurred_at: Time.current,
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:month:2026-03",
      facts: [],
      parseable_data: [],
      parse_status: "pending"
    )

    prompt = EntryDataParser.user_prompt(entry.input, entry: entry)

    assert_includes prompt, "Entry source: healthkit"
    assert_includes prompt, "Entry reference: healthkit:month:2026-03"
  end

  test "multimodal parsing uses configured model without mini fallback" do
    preference = AppSetting.current
    preference.llm_provider = "openrouter"
    preference.llm_model = "openai/gpt-5.4"

    assert_equal [ "openai/gpt-5.4" ], EntryDataParser.multimodal_models_for(preference)
  end

  test "attachment retry prompt tells model not to return empty facts for readable scans" do
    person = Person.create!(name: "OCR Prompt", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(input: "scan", occurred_at: Time.current, parse_status: "pending")

    prompt = EntryDataParser.attachment_ocr_retry_prompt(entry.input, entry: entry)

    assert_includes prompt, "OCR the rendered pages carefully"
    assert_includes prompt, "Do not return an empty facts array"
  end

  test "parser prompt tells document parser to extract diagnosis or symptom from medical admin documents" do
    prompt = EntryDataParser.system_prompt

    assert_includes prompt, "extract the medically relevant content too, not just the document purpose"
    assert_includes prompt, "If a document mentions a diagnosis, symptom, reason for visit, or reason for work incapacity"
    assert_includes prompt, "2022-01 Erkältung AU.pdf"
    assert_includes prompt, '"kind": "symptom"'
  end

  test "sanitizes document metadata" do
    result = EntryDataParser.sanitize_document({ "type" => "lab_report", "title" => "Laborblatt vom 06.04.2018", "extra" => "ignored" })

    assert_equal({ "type" => "lab_report", "title" => "Laborblatt vom 06.04.2018" }, result)
  end

  test "drops hallucinated document metadata when entry has no attachments" do
    person = Person.create!(name: "HealthKit No Document", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(
      input: "Apple Health daily summary for April 07, 2026.\n- Source: Apple Health.",
      occurred_at: Time.current,
      parse_status: "pending",
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:day:2026-04-07"
    )

    preference = AppSetting.current
    preference.llm_provider = "ollama"
    preference.llm_model = "llama3"
    preference.save!

    chat_singleton = LlmChatRequest.singleton_class
    chat_singleton.alias_method :__original_call_for_no_document_test, :call

    chat_singleton.define_method(:call) do |**|
      LlmChatRequest::Response.new(
        content: {
          document: { type: "lab_report", title: "Laborblatt vom 06.04.2018" },
          facts: [
            { text: "Apple Health daily summary", kind: "summary", value: "Apple Health", quality: "daily" }
          ],
          occurred_at: nil,
          llm: { status: "structured", confidence: "high", note: "Canonical structured facts extracted successfully." }
        }.to_json,
        status_code: 200,
        body: "{}"
      )
    end

    result = EntryDataParser.call(input: entry.input, preference:, entry: entry)

    assert_equal({}, result.document)
    assert_equal "Apple Health", result.fact_objects.first["value"]
  ensure
    if chat_singleton.method_defined?(:__original_call_for_no_document_test)
      chat_singleton.alias_method :call, :__original_call_for_no_document_test
      chat_singleton.remove_method :__original_call_for_no_document_test
    end
  end

  test "infers occurred_at from document title date when llm omits it" do
    person = Person.create!(name: "Document Date", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.build(input: "", occurred_at: Time.current, parse_status: "pending")
    entry.documents.attach(
      io: StringIO.new("%PDF fake"),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
    entry.save!

    payload = {
      "document" => { "type" => "invoice", "title" => "Zahnarztrechnung vom 24.03.2023" },
      "facts" => [ { "text" => "Zahnarztrechnung vom 24.03.2023", "kind" => "summary" } ],
      "occurred_at" => nil,
      "llm" => { "status" => "structured", "confidence" => "high", "note" => "Canonical structured facts extracted successfully." }
    }

    assert_equal Time.zone.local(2023, 3, 24), EntryDataParser.inferred_occurred_at(payload, entry: entry)
  end

  test "enriches healthkit summaries with lab results and native measurements" do
    person = Person.create!(name: "HealthKit Parse", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(
      input: "Apple Health daily summary for April 05, 2026.\n- Source: Apple Health.\n- Summary type: daily.\n- Period: April 05, 2026.\n- Step count 3972 count.\n- Walking and running distance 2.78 km.\n- Active energy burned 150.55 kcal.\n- Weight 97 kg.",
      occurred_at: Time.current,
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:day:2026-04-05",
      facts: [],
      parseable_data: [],
      parse_status: "pending"
    )

    preference = AppSetting.current
    preference.llm_provider = "ollama"
    preference.llm_model = "llama3"
    preference.save!

    chat_singleton = LlmChatRequest.singleton_class
    chat_singleton.alias_method :__original_chat_call_for_healthkit_test, :call

    chat_singleton.define_method(:call) do |**|
      LlmChatRequest::Response.new(
        content: {
          facts: [ "Step count 3972", "Walking and running distance 2.78 km", "Weight 97 kg" ],
          parseable_data: [ { type: "healthkit_summary", value: "Apple Health", quality: "daily" } ],
          occurred_at: nil,
          llm_response: { status: "structured", confidence: "high", note: "Apple Health summary parsed." }
        }.to_json,
        status_code: 200,
        body: "{}"
      )
    end

    result = EntryDataParser.call(input: entry.input, preference:, entry: entry)

    assert_includes result.fact_objects, { "text" => "Apple Health daily summary", "kind" => "summary", "value" => "Apple Health", "quality" => "daily" }
    assert_includes result.fact_objects, { "text" => "Weight 97 kg", "kind" => "measurement", "metric" => "weight", "value" => 97, "unit" => "kg" }
    assert_includes result.fact_objects, { "text" => "Step count 3972 count", "kind" => "measurement", "metric" => "step_count", "value" => 3972, "unit" => "count" }
    assert_includes result.fact_objects, { "text" => "Walking and running distance 2.78 km", "kind" => "measurement", "metric" => "walking_distance", "value" => 2.78, "unit" => "km" }
    assert_includes result.fact_objects, { "text" => "Active energy burned 150.55 kcal", "kind" => "measurement", "metric" => "active_energy", "value" => 150.55, "unit" => "kcal" }
  ensure
    if chat_singleton.method_defined?(:__original_chat_call_for_healthkit_test)
      chat_singleton.alias_method :call, :__original_chat_call_for_healthkit_test
      chat_singleton.remove_method :__original_chat_call_for_healthkit_test
    end
  end

  test "normalizes pulse units to bpm in healthkit summaries" do
    person = Person.create!(name: "Pulse Normalize", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(
      input: "Apple Health monthly summary for May 2025.\n- Source: Apple Health.\n- Summary type: monthly.\n- Period: May 2025.\n- Pulse avg 121.42 count/min; min 83; max 171.\n- Resting pulse avg 1.1 count/s; min 0.9; max 1.2.",
      occurred_at: Time.current,
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:month:2025-05",
      facts: [],
      parseable_data: [],
      parse_status: "pending"
    )

    result = EntryDataParser.send(:enrich_healthkit_parseable_data, [], entry.input, entry: entry)

    assert_includes result, { "type" => "healthkit_summary", "value" => "Apple Health", "quality" => "monthly" }
    assert_includes result, { "type" => "pulse", "value" => 121.42, "unit" => "bpm" }
    assert result.none? { |item| item["type"] == "pulse" && item["unit"].to_s.include?("count") }
  end
end
