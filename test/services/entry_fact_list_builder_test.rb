require "test_helper"

class EntryFactListBuilderTest < ActiveSupport::TestCase
  test "builds facts for bottle and diaper parseable_data" do
    facts = EntryFactListBuilder.call([
      { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" },
      { "type" => "diaper", "wet" => true, "solid" => false, "rash" => true }
    ])

    assert_equal [ "Bottle feeding 120 ml", "Diaper wet and rash" ], facts
  end

  test "builds facts for breast feeding with side" do
    facts = EntryFactListBuilder.call([
      { "type" => "breast_feeding", "value" => 17, "unit" => "min", "side" => "left" }
    ])

    assert_equal [ "Breast feeding Left 17 min" ], facts
  end

  test "falls back for unknown structured types" do
    facts = EntryFactListBuilder.call([
      { "type" => "oxygen_saturation", "value" => 97, "unit" => "%" }
    ])

    assert_equal [ "Oxygen saturation 97 %" ], facts
  end

  test "skips invalid fact items" do
    facts = EntryFactListBuilder.call([
      nil,
      "oops",
      { "value" => 10 },
      { "type" => "medication", "value" => "ibuprofen", "dose" => "400mg" }
    ])

    assert_equal [ "Medication ibuprofen 400mg" ], facts
  end
end
