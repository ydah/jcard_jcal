# frozen_string_literal: true

require_relative "param_codec"

module JCardJCal
  module ContentLine
    # Serializes an already encoded property value, folding at UTF-8 boundaries.
    module Writer
      module_function

      def line(name:, params:, value:, group: nil)
        validate_name(name)
        validate_name(group) unless group.nil?
        value = value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String)
        unless value.is_a?(String) && value.valid_encoding? &&
               !value.match?(/[\x00-\x08\x0a-\x1f\x7f]/)
          raise ValueError, "Property value must be a string without line breaks or control characters"
        end
        raise ValueError, "Parameters must be a hash" unless params.is_a?(Hash)

        content = group ? "#{group}.#{name.upcase}" : name.upcase
        seen = {}
        params.each do |key, parameter|
          validate_name(key)
          raise ValueError, "Duplicate parameter #{key}" if seen[key.downcase]

          seen[key.downcase] = true
          values = parameter.is_a?(Array) ? parameter : [parameter]
          raise ValueError, "Parameter lists cannot be empty" if values.empty?

          content << ";#{key.upcase}=#{values.map { |item| ParamCodec.encode(item) }.join(",")}"
        end
        content << ":#{value}"
        content.force_encoding(Encoding::UTF_8)
        result = String.new
        width = 0
        content.each_char do |character|
          if width + character.bytesize > 75
            result << "\r\n "
            width = 1
          end
          result << character
          width += character.bytesize
        end
        result << "\r\n"
      end

      def validate_name(name)
        unless name.is_a?(String) && name.valid_encoding? && name.encoding.ascii_compatible? &&
               name.match?(/\A[A-Za-z0-9-]+\z/)
          raise ValueError, "Invalid property, group, or parameter name"
        end
      end
      private_class_method :validate_name
    end
  end
end
