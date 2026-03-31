require "test_helper"

class EntryDataParserTest < ActiveSupport::TestCase
  test "system prompt includes baby and broader structured examples" do
    prompt = EntryDataParser.system_prompt

    assert_includes prompt, "Trinken"
    assert_includes prompt, "Doctor appointment"
    assert_includes prompt, "RSV Impfung"
    assert_includes prompt, '"facts"'
    assert_includes prompt, '"parseable_data"'
  end

  test "call sanitizes fenced json objects" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_note, _preference, entry: nil|
      <<~JSON
        ```json
        {"facts":["  Breast feeding left 18 minutes  ",""],"parseable_data":[{"type":"breastfeeding","value":"18","unit":"minutes","side":"left"}],"occurred_at":"2026-03-30T10:05:00Z","llm_response":{"status":"structured","confidence":"high","note":"Canonical structured data extracted successfully."}}
        ```
      JSON
    end

    begin
      result = EntryDataParser.call(input: "Peter breastfed left side for 18 minutes", preference: preference)

      assert_nil result.error
      assert_equal [ "Breast feeding left 18 minutes" ], result.facts
      assert_equal [ { "type" => "breast_feeding", "value" => 18, "unit" => "min", "side" => "left" } ], result.parseable_data
      assert_equal Time.zone.parse("2026-03-30T10:05:00Z"), result.occurred_at
      assert_equal({ "status" => "structured", "confidence" => "high", "note" => "Canonical structured data extracted successfully." }, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "request completion sends system prompt and input" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    fake_response = Struct.new(:code, :body).new("200", { choices: [ { message: { content: "[]" } } ] }.to_json)

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| fake_response }
      block.call(http)
    end

    begin
      EntryDataParser.request_completion("Peter has fever 39.2", preference)
    ensure
      http_singleton.alias_method :start, :__original_start_for_test
      http_singleton.remove_method :__original_start_for_test
    end

    payload = JSON.parse(LlmLog.order(:created_at).last.request_payload)
    assert_equal "llama3", payload["model"]
    assert_equal 0, payload["temperature"]
    assert_includes payload["messages"][0]["content"], "RSV Impfung"
    assert_includes payload["messages"][1]["content"], "Current time:"
    assert_includes payload["messages"][1]["content"], "Time zone:"
    assert_includes payload["messages"][1]["content"], "Input: Peter has fever 39.2"
  end

  test "call returns request_failed when response is not the expected object" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_note, _preference, entry: nil|
      "[]"
    end

    begin
      result = EntryDataParser.call(input: "Peter has fever 39.2", preference: preference)

      assert_equal :request_failed, result.error
      assert_equal [], result.facts
      assert_equal [], result.parseable_data
      assert_nil result.occurred_at
      assert_equal({}, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call retries once when first response is empty" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    attempts = 0
    EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
      attempts += 1
      attempts == 1 ? "" : '{"facts":["Weight 53 cm"],"parseable_data":[{"type":"height","value":"53","unit":"cm"}],"occurred_at":null,"llm_response":{"status":"structured","confidence":"high","note":"Canonical structured data extracted successfully."}}'
    end

    begin
      result = EntryDataParser.call(input: "53cm Körpergröße", preference: preference)

      assert_nil result.error
      assert_equal 2, attempts
      assert_equal [ "Weight 53 cm" ], result.facts
      assert_equal [ { "type" => "height", "value" => 53, "unit" => "cm" } ], result.parseable_data
      assert_equal({ "status" => "structured", "confidence" => "high", "note" => "Canonical structured data extracted successfully." }, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call fails after retry budget is exhausted" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    attempts = 0
    EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
      attempts += 1
      ""
    end

    begin
      result = EntryDataParser.call(input: "still broken", preference: preference)

      assert_equal :request_failed, result.error
      assert_equal 2, attempts
      assert_equal [], result.facts
      assert_equal [], result.parseable_data
      assert_equal({}, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call falls back to canonical todo when llm returns no usable response for simple reminder" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
      ""
    end

    begin
      result = EntryDataParser.call(input: "Check füsse", preference: preference)

      assert_nil result.error
      assert_equal [ "Check füsse" ], result.facts
      assert_equal [ { "type" => "todo", "value" => "Check füsse" } ], result.parseable_data
      assert_equal "structured", result.llm_response["status"]
      assert_equal "low", result.llm_response["confidence"]
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call drops invalid fact items and keeps canonical structured diaper parseable_data" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_note, _preference, entry: nil|
      <<~JSON
        {"facts":["Diaper wet and rash",123,null,"  "],"parseable_data":[{"type":"diaper","wet":"true","solid":"false","rash":"true"},{"type":"bottle","value":"120","unit":"mls"}],"llm_response":{"status":"structured","confidence":"medium","note":"Structured diaper and bottle data extracted."}}
      JSON
    end

    begin
      result = EntryDataParser.call(input: "diaper wet and rash plus bottle 120ml", preference: preference)

      assert_nil result.error
      assert_equal [ "Diaper wet and rash", "123" ], result.facts
      assert_equal(
        [
          { "type" => "diaper", "wet" => true, "solid" => false, "rash" => true },
          { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" }
        ],
        result.parseable_data
      )
      assert_nil result.occurred_at
      assert_equal({ "status" => "structured", "confidence" => "medium", "note" => "Structured diaper and bottle data extracted." }, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call normalizes many supported input shapes" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    cases = [
      {
        response: '{"facts":["Temperature 38.4 C high"],"parseable_data":[{"type":"temp","value":"38.4","unit":"celsius","flag":"HIGH"}]}',
        expected_facts: [ "Temperature 38.4 C high" ],
        expected_parseable_data: [ { "type" => "temperature", "value" => 38.4, "unit" => "C", "flag" => "high" } ]
      },
      {
        response: '{"facts":["Pulse 128 bpm"],"parseable_data":[{"type":"heart_rate","value":"128","unit":"beats/min"}]}',
        expected_facts: [ "Pulse 128 bpm" ],
        expected_parseable_data: [ { "type" => "pulse", "value" => 128, "unit" => "bpm" } ]
      },
      {
        response: '{"facts":["Weight 75 kg"],"parseable_data":[{"type":"weight","value":"75","unit":"kg"}]}',
        expected_facts: [ "Weight 75 kg" ],
        expected_parseable_data: [ { "type" => "weight", "value" => 75, "unit" => "kg" } ]
      },
      {
        response: '{"facts":["Bottle feeding 120 ml"],"parseable_data":[{"type":"bottle","value":"120","unit":"mls"}]}',
        expected_facts: [ "Bottle feeding 120 ml" ],
        expected_parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
      },
      {
        response: '{"facts":["Breast feeding left 18 min"],"parseable_data":[{"type":"nursing","value":"18","unit":"minutes","side":"left"}]}',
        expected_facts: [ "Breast feeding left 18 min" ],
        expected_parseable_data: [ { "type" => "breast_feeding", "value" => 18, "unit" => "min", "side" => "left" } ]
      },
      {
        response: '{"facts":["Breast feeding right 7 min"],"parseable_data":[{"type":"breastfeeding","value":"7","unit":"mins","side":"right"}]}',
        expected_facts: [ "Breast feeding right 7 min" ],
        expected_parseable_data: [ { "type" => "breast_feeding", "value" => 7, "unit" => "min", "side" => "right" } ]
      },
      {
        response: '{"facts":["Diaper wet and solid"],"parseable_data":[{"type":"diaper","wet":"true","solid":"true"}]}',
        expected_facts: [ "Diaper wet and solid" ],
        expected_parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => true } ]
      },
      {
        response: '{"facts":["Medication ibuprofen 400mg","Symptom knee pain"],"parseable_data":[{"type":"medication","value":"ibuprofen","dose":"400mg"},{"type":"symptom","value":"knee pain"}]}',
        expected_facts: [ "Medication ibuprofen 400mg", "Symptom knee pain" ],
        expected_parseable_data: [ { "type" => "medication", "value" => "ibuprofen", "dose" => "400mg" }, { "type" => "symptom", "value" => "knee pain" } ]
      },
      {
        response: '{"facts":["RSV-Impfung am Sonntag"],"parseable_data":[{"type":"impfung","value":"RSV"}]}',
        expected_facts: [ "RSV-Impfung am Sonntag" ],
        expected_parseable_data: [ { "type" => "vaccination", "value" => "RSV" } ]
      },
      {
        response: '{"facts":["Sleep 95 min"],"parseable_data":[{"type":"sleep","value":"95","unit":"minutes"}]}',
        expected_facts: [ "Sleep 95 min" ],
        expected_parseable_data: [ { "type" => "sleep", "value" => 95, "unit" => "min" } ]
      },
      {
        response: '{"facts":["General note seems fine today"],"parseable_data":[]}',
        expected_facts: [ "General note seems fine today" ],
        expected_parseable_data: []
      }
    ]

    original_method = EntryDataParser.method(:request_completion)

    cases.each do |test_case|
      EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
        test_case[:response]
      end

      result = EntryDataParser.call(input: "sample", preference: preference)

      assert_nil result.error
      assert_equal test_case[:expected_facts], result.facts
      assert_equal test_case[:expected_parseable_data], result.parseable_data
      assert_equal({}, result.llm_response)
    end
  ensure
    EntryDataParser.define_singleton_method(:request_completion, original_method)
  end

  test "call returns empty outputs when fact list and parseable_data are absent" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_note, _preference, entry: nil|
      "{}"
    end

    begin
      result = EntryDataParser.call(input: "nothing useful", preference: preference)

      assert_nil result.error
      assert_equal [], result.facts
      assert_equal [], result.parseable_data
      assert_nil result.occurred_at
      assert_equal({}, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "system prompt requires a fact even without parseable data" do
    prompt = EntryDataParser.system_prompt

    assert_includes prompt, "Facts must be short strings"
    assert_includes prompt, "Always use English canonical schema"
    assert_includes prompt, "Always try to return the best useful `facts` and the best useful `parseable_data` you can."
    assert_includes prompt, "prefer that exact canonical type"
    assert_includes prompt, "Return at most one `todo` item per entry"
    assert_includes prompt, "Medical findings, measurements, symptoms, vaccinations, medication, vitals"
    assert_includes prompt, '"type": "appointment"'
    assert_includes prompt, '"type": "todo"'
    assert_not_includes prompt, '"type": "note"'
    assert_includes prompt, '"llm_response"'
    assert_includes prompt, '"occurred_at": null'
    assert_includes prompt, '"status": "structured"'
  end

  test "call keeps occurred_at nil when llm returns null" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
      '{"facts":["General note seems fine today"],"parseable_data":[],"occurred_at":null,"llm_response":{"status":"facts_only","confidence":"medium","note":"No canonical structured data could be extracted from the note."}}'
    end

    begin
      result = EntryDataParser.call(input: "an old plain note", preference: preference)
      assert_nil result.occurred_at
      assert_equal({ "status" => "facts_only", "confidence" => "medium", "note" => "No canonical structured data could be extracted from the note." }, result.llm_response)
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "call parses inferred occurred_at timestamps" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    original_method = EntryDataParser.method(:request_completion)
    EntryDataParser.define_singleton_method(:request_completion) do |_input, _preference, entry: nil|
      '{"facts":["General note happened yesterday at 10:05"],"parseable_data":[],"occurred_at":"2026-03-30T10:05:00+00:00","llm_response":{"status":"facts_only","confidence":"medium","note":"Time was inferred but no canonical structured data was extracted."}}'
    end

    begin
      travel_to Time.zone.local(2026, 3, 31, 12, 0, 0) do
        result = EntryDataParser.call(input: "bla bla happened yesterday at 10:05", preference: preference)
        assert_equal Time.zone.local(2026, 3, 30, 10, 5, 0), result.occurred_at
        assert_equal({ "status" => "facts_only", "confidence" => "medium", "note" => "Time was inferred but no canonical structured data was extracted." }, result.llm_response)
      end
    ensure
      EntryDataParser.define_singleton_method(:request_completion, original_method)
    end
  end

  test "ready is false without model" do
    preference = UserPreference.current
    preference.update!(llm_provider: "openai", llm_model: nil)

    assert_not EntryDataParser.ready?(preference)
    assert_equal :missing_model, EntryDataParser.configuration_error_for(preference)
  end
end
