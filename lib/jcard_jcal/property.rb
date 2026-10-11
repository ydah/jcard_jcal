# frozen_string_literal: true

module JCardJCal
  # A jCard/jCal property, retaining unrecognized parameters and values.
  class Property
    attr_reader :warnings

    def initialize(data, registry: nil, strict: true, pointer: "", line_number: nil, max_binary_size: 1_048_576)
      @registry = registry || default_registry
      @pointer = pointer
      @line_number = line_number
      @max_binary_size = max_binary_size
      @warnings = []
      @data = data
      unless data.is_a?(Array) && data.size >= 4 && data[0].is_a?(String) && data[1].is_a?(Hash) && data[2].is_a?(String)
        raise ParseError.new("property must contain a name, parameters, type and value", pointer: pointer, line_number: line_number)
      end

      validate!
      @data = copy(data)
    rescue ValidationError => e
      raise if strict || e.is_a?(LimitError)

      @warnings << e
      @data = copy(data)
    end

    def name = @data[0]
    def params = copy(@data[1])
    def type = @data[2]
    def values = copy(@data[3..])
    def group = @data[1]["group"]
    def to_a = copy(@data)

    def validate!
      fail_at("property must contain a name, parameters, type and value") unless @data.is_a?(Array) && @data.size >= 4
      @data[3..].each_with_index { |value, index| validate_binary_size(value, "/#{index + 3}") } if @data[2].casecmp?("binary")
      fail_at("invalid property name", "/0") unless token?(@data[0]) && !%w[begin end].include?(@data[0])
      validate_params
      fail_at("invalid value type", "/2") unless token?(@data[2])
      definition = @registry[@data[0]]
      allowed = definition["types"]
      if @data[2] != "unknown" && (definition["type"] != "unknown" || definition["value_required"]) && allowed && !allowed.include?(@data[2])
        fail_at("value type is not allowed for this property", "/2")
      end
      fail_at("property requires a single value", "/3") if definition["source"] && !definition["multiple"] && @data.size != 4
      @data[3..].each_with_index { |value, index| validate_value(value, "/#{index + 3}") }
      self
    end

    private

    def copy(value)
      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError => e
      raise ParseError.new(e.message, pointer: @pointer, line_number: @line_number)
    end

    def token?(value) = value.is_a?(String) && /\A[a-z0-9-]+\z/.match?(value)

    def validate_params
      fail_at("parameters must be an object", "/1") unless @data[1].is_a?(Hash)
      @data[1].each do |key, value|
        path = "/1/#{key.to_s.gsub("~", "~0").gsub("/", "~1")}"
        fail_at("invalid parameter name", path) unless token?(key) && key != "value"
        valid = value.is_a?(String) || (value.is_a?(Array) && !value.empty? && value.all?(String))
        fail_at("parameter must be a string or nonempty array of strings", path) unless valid
        validate_parameter_value(value, path)
        fail_at("invalid group parameter", path) if format == :vcard && key == "group" && (!value.is_a?(String) || !/\A[a-zA-Z0-9-]+\z/.match?(value))
      end
    end

    def validate_parameter_value(value, path)
      Array(value).each { |item| ContentLine::ParamCodec.encode(item) }
    rescue ValueError => e
      fail_at(e.message, path, e.class)
    end

    def validate_value(value, path)
      definition = @registry[name]
      structured = definition["structured"] || (!definition["source"] && type == "text" && value.is_a?(Array))
      return validate_scalar(value, path) unless structured && type != "unknown"

      parts = value.is_a?(Array) ? value : [value]
      counts = definition["components"]
      fail_at("invalid number of structured components", path) if parts.empty? || (counts && !counts.include?(parts.size))
      parts.each_with_index do |part, index|
        if part.is_a?(Array)
          fail_at("component lists are not allowed", "#{path}/#{index}") unless (definition["component_multiple"] || !definition["source"]) && !part.empty?
          part.each_with_index { |item, subindex| validate_scalar(item, "#{path}/#{index}/#{subindex}") }
        else
          validate_scalar(part, "#{path}/#{index}")
        end
      end
    end

    def validate_scalar(value, path)
      ValueTypes.from_json(value, type, format: format, max_binary_size: @max_binary_size)
    rescue ValueError => e
      fail_at(e.message, path, e.class)
    end

    def validate_binary_size(value, path)
      ValueTypes.validate_binary_size(value, @max_binary_size)
    rescue LimitError => e
      fail_at(e.message, path, LimitError)
    end

    def fail_at(message, suffix = "", error_class = ValidationError)
      raise error_class.new(message, pointer: "#{@pointer}#{suffix}", line_number: @line_number)
    end
  end
end
