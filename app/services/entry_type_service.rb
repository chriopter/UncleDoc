# Service to manage entry type definitions from YAML
# This allows adding new health tracking types without code changes
class EntryTypeService
  CONFIG_PATH = Rails.root.join("config/entry_types.yml")

  class << self
    def all
      @all ||= load_types
    end

    def find(type_name)
      all[type_name.to_s]
    end

    def exists?(type_name)
      all.key?(type_name.to_s)
    end

    def label_for(type_name, locale = I18n.locale)
      type = find(type_name)
      return type_name.to_s unless type

      type.dig("label", locale.to_s) || type.dig("label", "en") || type_name.to_s
    end

    def icon_for(type_name)
      find(type_name)&.dig("icon") || "note"
    end

    def color_for(type_name)
      find(type_name)&.dig("color") || "slate"
    end

    def fields_for(type_name)
      find(type_name)&.dig("fields") || {}
    end

    def baby_types
      all.keys.select { |k| k.start_with?("baby_") }
    end

    def health_types
      all.keys.select { |k| k.start_with?("health_") }
    end

    private

    def load_types
      YAML.load_file(CONFIG_PATH)&.dig("entry_types") || {}
    rescue Errno::ENOENT
      {}
    end
  end
end

# Reload in development
Rails.application.config.to_prepare do
  EntryTypeService.instance_variable_set(:@all, nil)
end if Rails.env.development?
