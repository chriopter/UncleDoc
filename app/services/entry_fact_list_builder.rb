class EntryFactListBuilder
  def self.call(parseable_data, locale: I18n.locale)
    I18n.with_locale(locale) do
      Array(parseable_data).filter_map do |item|
      next unless item.is_a?(Hash)
      next if item["type"].blank?

      case item["type"]
      when "temperature"
        build_measurement_fact(label_for("temperature"), item["value"], item["unit"], suffix: item["flag"])
      when "pulse"
        build_measurement_fact(label_for("pulse"), item["value"], item["unit"])
      when "blood_pressure"
        values = [ item["systolic"], item["diastolic"] ].compact.join("/")
        build_measurement_fact(label_for("blood_pressure"), values.presence, item["unit"])
      when "weight"
        build_measurement_fact(label_for("weight"), item["value"], item["unit"])
      when "height"
        build_measurement_fact(label_for("height"), item["value"], item["unit"])
      when "bottle_feeding"
        build_measurement_fact(label_for("bottle_feeding"), item["value"], item["unit"])
      when "breast_feeding"
        side = side_label(item["side"])
        detail = [ side&.humanize, item["value"], item["unit"] ].compact.join(" ")
        [ label_for("breast_feeding"), detail.presence ].compact.join(" ")
      when "diaper"
        states = []
        states << value_label("wet") if item["wet"] == true
        states << value_label("solid") if item["solid"] == true
        states << value_label("rash") if item["rash"] == true
        [ label_for("diaper"), join_states(states).presence ].compact.join(" ")
      when "sleep"
        build_measurement_fact(label_for("sleep"), item["value"], item["unit"])
      when "medication"
        detail = [ item["value"], item["dose"] ].compact.join(" ")
        [ label_for("medication"), detail.presence ].compact.join(" ")
      when "lab_result"
        detail = [ item["value"], item["result"], item["unit"] ].compact.join(" ")
        detail = [ detail, item["ref"] ].compact.join(" (") if item["ref"].present?
        detail = "#{detail})" if item["ref"].present?
        detail = [ detail, item["flag"] ].compact.join(" ")
        [ label_for("lab_result"), detail.presence ].compact.join(": ")
      when "vaccination"
        detail = [ item["value"], item["dose"] ].compact.join(" ")
        [ label_for("vaccination"), detail.presence ].compact.join(" ")
      when "appointment"
        detail = [ item["value"], item["location"], item["quality"] ].compact.join(" • ")
        [ label_for("appointment"), detail.presence ].compact.join(": ")
      when "todo"
        detail = [ item["value"], item["location"], item["quality"] ].compact.join(" • ")
        [ label_for("todo"), detail.presence ].compact.join(": ")
      when "note"
        detail = [ item["value"], item["quality"] ].compact.join(" • ")
        [ label_for("note"), detail.presence ].compact.join(": ")
      when "symptom"
        [ label_for("symptom"), item["value"].presence ].compact.join(": ")
      else
        detail = [ item["value"], item["unit"], item["dose"], item["flag"] ].compact.join(" ")
        [ item["type"].to_s.humanize, detail.presence ].compact.join(" ")
      end
      end.filter_map(&:presence)
    end
  end

  def self.build_measurement_fact(label, value, unit, suffix: nil)
    detail = [ value, unit ].compact.join(" ")
    detail = [ detail, suffix ].compact.join(" ") if suffix.present?
    [ label, detail.presence ].compact.join(" ")
  end

  def self.label_for(type)
    I18n.t("entries.fact_labels.#{type}")
  end

  def self.value_label(value)
    I18n.t("entries.data_values.#{value}")
  end

  def self.side_label(side)
    return if side.blank?

    I18n.t("entries.data_values.side_#{side}")
  end

  def self.join_states(states)
    case states.length
    when 0 then nil
    when 1 then states.first
    when 2 then states.join(" #{I18n.t('entries.fact_joiners.and')} ")
    else
      [ states[0..-2].join(", "), states.last ].join(" #{I18n.t('entries.fact_joiners.and')} ")
    end
  end
  private_class_method :build_measurement_fact
  private_class_method :label_for, :value_label, :side_label, :join_states
end
