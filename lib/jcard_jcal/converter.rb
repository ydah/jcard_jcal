# frozen_string_literal: true

module JCardJCal
  # Shared conversion of component trees and their property values.
  class Converter
    def initialize(format:, registry: nil, strict: true, max_depth: 32, max_properties: 10_000,
                   max_line_length: 1_048_576, max_binary_size: 1_048_576, max_input_size: 16_777_216)
      @format = format
      @registry = registry || (format == :vcard ? JCard::Registry.default : JCal::Registry.default)
      @strict = strict
      @limits = { depth: max_depth, properties: max_properties, line_length: max_line_length,
                  binary_size: max_binary_size, input_size: max_input_size }
      raise ArgumentError, "limits must be positive integers" unless @limits.values.all? { |n| n.is_a?(Integer) && n.positive? }

      @property_count = 0
    end

    def parse_json(source)
      check_source(source)
      data = JSON.parse(source, max_nesting: (@limits[:depth] * 3) + 10, allow_duplicate_key: false)
      expected = @format == :vcard ? "vcard" : "vcalendar"
      raise ParseError, "expected #{expected} component" unless data.is_a?(Array) && data.first == expected

      read_component(data, "", 1)
    rescue JSON::ParserError => e
      raise ParseError, e.message
    end

    def parse_text(source)
      check_source(source)
      roots = []
      stack = []
      ContentLine::Reader.new(source, max_line_length: @limits[:line_length]).each do |line|
        case line.name
        when "begin"
          begin_component(line, stack)
        when "end"
          end_component(line, stack, roots)
        else
          raise ParseError.new("property outside a component", line_number: line.line_number) if stack.empty?

          count_property!(line_number: line.line_number)
          prop = read_property(line)
          stack.last[:properties] << prop
          stack.last[:warnings].concat(prop.warnings)
        end
      end
      raise ParseError, "missing END content line" unless stack.empty?
      raise ParseError, "no component found" if roots.empty?
      return roots if @format == :vcard

      raise ParseError, "expected exactly one VCALENDAR" unless roots.size == 1

      roots.first
    end

    def self.write(component, format:, registry: nil, max_binary_size: 1_048_576)
      new(format: format, registry: registry, max_binary_size: max_binary_size).write_component(component)
    end

    def write_component(component)
      writer = ContentLine::Writer
      result = writer.line(name: "begin", params: {}, value: component.name.upcase)
      properties = component.properties
      properties = properties.partition { |property| property.name == "version" }.flatten if @format == :vcard
      properties.each { |property| result << write_property(property) }
      component.components.each { |child| result << write_component(child) }
      result << writer.line(name: "end", params: {}, value: component.name.upcase)
    end

    private

    def check_source(source)
      raise ParseError, "input must be a string" unless source.is_a?(String)
      raise ParseError, "input size limit exceeded" if source.bytesize > @limits[:input_size]
    end

    def count_property!(**location)
      @property_count += 1
      raise ParseError.new("property count limit exceeded", **location) if @property_count > @limits[:properties]
    end

    def read_component(data, pointer, depth)
      raise ParseError.new("component depth limit exceeded", pointer: pointer) if depth > @limits[:depth]

      size = @format == :vcard ? 2 : 3
      valid = data.is_a?(Array) && data.size == size && data[0].is_a?(String) && /\A[a-z0-9-]+\z/.match?(data[0]) && data[1].is_a?(Array)
      valid &&= data[2].is_a?(Array) if @format == :ical
      raise ParseError.new("invalid component structure", pointer: pointer) unless valid

      props = data[1].each_with_index.map do |raw, index|
        path = "#{pointer}/1/#{index}"
        count_property!(pointer: path)
        property_class.new(raw, **property_options, pointer: path)
      end
      children = @format == :ical ? data[2].each_with_index.map { |child, index| read_component(child, "#{pointer}/2/#{index}", depth + 1) } : []
      build_component(data[0], props, children, props.flat_map(&:warnings) + children.flat_map(&:warnings))
    end

    def begin_component(line, stack)
      validate_boundary(line)
      name = line.value.downcase
      expected = @format == :vcard ? "vcard" : "vcalendar"
      raise ParseError.new("expected #{expected} component", line_number: line.line_number) if stack.empty? && name != expected
      if (@format == :vcard && !stack.empty?) || stack.size >= @limits[:depth]
        raise ParseError.new("component depth limit exceeded", line_number: line.line_number)
      end

      stack << { name: name, properties: [], children: [], warnings: [] }
    end

    def end_component(line, stack, roots)
      validate_boundary(line)
      raise ParseError.new("BEGIN/END mismatch", line_number: line.line_number) if stack.empty? || stack.last[:name] != line.value.downcase

      frame = stack.pop
      component = build_component(frame[:name], frame[:properties], frame[:children], frame[:warnings])
      if stack.empty?
        roots << component
      else
        stack.last[:children] << component
        stack.last[:warnings].concat(component.warnings)
      end
    end

    def validate_boundary(line)
      return if line.group.nil? && line.params.empty? && /\A[a-zA-Z0-9-]+\z/.match?(line.value)

      raise ParseError.new("invalid component boundary", line_number: line.line_number)
    end

    def build_component(name, properties, children, warnings)
      klass = if @format == :vcard
                JCard::Card
              elsif name == "vcalendar"
                JCal::Calendar
              else
                JCal::Component
              end
      result = klass.new(name, properties, children, warnings: warnings, registry: @registry, max_binary_size: @limits[:binary_size])
      begin
        result.validate!
      rescue ValidationError => e
        raise if @strict || e.is_a?(LimitError)

        warnings << e unless warnings.any? { |warning| warning.message == e.message }
      end
      result
    end

    def property_class = @format == :vcard ? JCard::Property : JCal::Property
    def property_options = { registry: @registry, strict: @strict, max_binary_size: @limits[:binary_size] }

    def read_property(line)
      params = line.params.dup
      if @format == :ical && (line.group || params["encoding"].is_a?(Array))
        raise ValidationError.new("iCalendar disallows groups and multiple ENCODING values", line_number: line.line_number)
      end

      explicit_type = params.delete("value")
      raise ParseError.new("VALUE must have one value", line_number: line.line_number) if explicit_type.is_a?(Array)
      if (@format == :vcard && params.key?("group")) || explicit_type&.casecmp?("unknown")
        raise ValidationError.new("reserved GROUP or UNKNOWN declaration", line_number: line.line_number)
      end

      params["group"] = line.group if line.group
      params["sort-as"] = params["sort-as"].split(",", -1) if @format == :vcard && params["sort-as"].is_a?(String) && params["sort-as"].include?(",")
      definition = @registry[line.name]
      type = explicit_type ? explicit_type.downcase : definition["type"]
      begin
        value = line.value
        if @format == :ical && type != "binary" && params["encoding"]&.casecmp?("BASE64")
          ValueTypes.from_json(value, "binary", format: :ical, max_binary_size: @limits[:binary_size])
          value = value.unpack1("m0").force_encoding(Encoding::UTF_8)
          params.delete("encoding")
        end
        values = parse_values(value, type, definition)
        property_class.new([line.name, params, type, *values], **property_options, strict: true, line_number: line.line_number)
      rescue ValueError, ValidationError => e
        located = e.class.new(e.message, line_number: line.line_number)
        raise located if @strict || e.is_a?(LimitError)

        property = property_class.new([line.name, params, "unknown", line.value], **property_options, line_number: line.line_number)
        property.warnings << located
        property
      end
    end

    def parse_values(value, type, definition)
      if definition["structured"] && type != "unknown"
        parts = ContentLine::TextCodec.split(value, ";").map do |part|
          raw_items = definition["component_multiple"] ? ContentLine::TextCodec.split(part, ",") : [part]
          items = raw_items.map { |item| parse_scalar(item, type) }
          items.size == 1 ? items.first : items
        end
        parts.size == 1 ? parts : [parts]
      else
        values = definition["multiple"] && type != "unknown" ? ContentLine::TextCodec.split(value, ",") : [value]
        values.map { |item| parse_scalar(item, type) }
      end
    end

    def parse_scalar(value, type)
      ValueTypes.from_text(value, type, format: @format, max_binary_size: @limits[:binary_size])
    end

    def write_property(property)
      property.validate!
      definition = @registry[property.name]
      params = property.params
      group = @format == :vcard ? params.delete("group") : nil
      params["sort-as"] = params["sort-as"].join(",") if @format == :vcard && params["sort-as"].is_a?(Array)
      params["encoding"] = "BASE64" if @format == :ical && property.type == "binary"
      params["value"] = property.type.upcase if property.type != "unknown" && (property.type != definition["type"] || definition["value_required"])
      values = property.values.map do |value|
        if value.is_a?(Array) && (definition["structured"] || property.type == "text")
          value.map { |part| Array(part).map { |item| write_scalar(item, property.type) }.join(",") }.join(";")
        else
          write_scalar(value, property.type)
        end
      end
      ContentLine::Writer.line(name: property.name, params: params, value: values.join(","), group: group)
    end

    def write_scalar(value, type)
      ValueTypes.to_text(value, type, format: @format, max_binary_size: @limits[:binary_size])
    end
  end
end
