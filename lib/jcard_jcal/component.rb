# frozen_string_literal: true

module JCardJCal
  # Ordered properties and nested components with lossless JSON serialization.
  class Component
    attr_reader :name, :warnings

    def initialize(name, properties, components = [], warnings: [], registry: nil, max_binary_size: 1_048_576)
      @name = name
      @properties = properties
      @components = components
      @warnings = warnings
      @registry = registry
      @max_binary_size = max_binary_size
    end

    def properties(name = nil)
      return @properties.dup unless name

      @properties.select { |property| property.name == name.downcase }
    end

    def property(name) = properties(name).first

    def components(name = nil)
      return @components.dup unless name

      @components.select { |component| component.name == name.downcase }
    end

    def to_a
      result = [@name, @properties.map(&:to_a)]
      result << @components.map(&:to_a) unless @name == "vcard"
      result
    end

    def to_json(*)
      validate!
      JSON.generate(to_a, *)
    end

    def validate!
      valid_name = @name.is_a?(String) && /\A[a-z0-9-]+\z/.match?(@name)
      valid_name &&= @name == "vcard" if is_a?(JCard::Card)
      valid_name &&= @name == "vcalendar" if is_a?(JCal::Calendar)
      raise ValidationError.new("invalid component name", pointer: "/0") unless valid_name
      unless @properties.is_a?(Array) && @properties.all?(Property) && @components.is_a?(Array) && @components.all?(Component)
        raise ValidationError, "invalid component children"
      end
      raise ValidationError, "vCard cannot contain components" if is_a?(JCard::Card) && !@components.empty?

      @properties.each(&:validate!)
      @components.each(&:validate!)
      return self unless @name == "vcard"

      versions = properties("version")
      unless versions.size == 1 && versions.first.type == "text" && versions.first.values == ["4.0"]
        raise ValidationError.new("vCard requires exactly one VERSION:4.0 property", pointer: "/1")
      end
      raise ValidationError.new("VERSION must be the first vCard property", pointer: "/1/0") unless @properties.first == versions.first

      self
    end

    private

    def to_text(format)
      validate!
      Converter.write(self, format: format, registry: @registry, max_binary_size: @max_binary_size)
    end
  end
end
