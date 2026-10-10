# frozen_string_literal: true

require "yaml"

module JCardJCal
  # Per-conversion registry: duplicate a frozen default to add application properties.
  class Registry
    UNKNOWN = { "type" => "unknown", "types" => ["unknown"].freeze, "multiple" => false,
                "structured" => false, "source" => nil }.freeze

    def initialize(entries = {})
      @entries = {}
      entries.each { |name, metadata| register(name, **metadata.transform_keys(&:to_sym)) }
    end

    def initialize_copy(other)
      super
      @entries = @entries.dup
    end

    def [](name)
      @entries.fetch(name.to_s.downcase, UNKNOWN)
    end

    def register(name, type:, types: nil, multiple: false, structured: false, **metadata)
      raise FrozenError, "duplicate the default registry before registering properties" if frozen?

      name = name.to_s.downcase
      type = type.to_s.downcase
      types = (types || [type]).map { |item| item.to_s.downcase }
      unless /\A[a-z0-9-]+\z/.match?(name) && /\A[a-z0-9-]+\z/.match?(type) &&
             !types.empty? && types.all? { |item| /\A[a-z0-9-]+\z/.match?(item) }
        raise ArgumentError, "invalid property name or value type"
      end

      @entries[name] = immutable(metadata.transform_keys(&:to_s).merge(
                                   "type" => type, "types" => types, "multiple" => multiple, "structured" => structured,
                                   "source" => metadata[:source]
                                 ))
      self
    end

    def freeze
      @entries.freeze
      super
    end

    def self.load(filename)
      new(YAML.safe_load_file(File.expand_path("../../data/#{filename}", __dir__))).freeze
    end

    private

    def immutable(value)
      case value
      when Hash then value.to_h { |key, item| [key.dup.freeze, immutable(item)] }.freeze
      when Array then value.map { |item| immutable(item) }.freeze
      when String then value.dup.freeze
      else value.freeze
      end
    end
  end
end

module JCard # rubocop:disable Style/OneClassPerFile
  class Registry < JCardJCal::Registry
    DEFAULT = load("vcard_properties.yml")

    def self.default
      DEFAULT
    end
  end
end

module JCal # rubocop:disable Style/OneClassPerFile
  class Registry < JCardJCal::Registry
    DEFAULT = load("ical_properties.yml")

    def self.default
      DEFAULT
    end
  end
end
