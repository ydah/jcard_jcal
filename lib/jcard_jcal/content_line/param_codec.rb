# frozen_string_literal: true

module JCardJCal
  module ContentLine
    # RFC 6868 escaping and content-line parameter quoting.
    module ParamCodec
      module_function

      def decode(value)
        value = validate(value)
        if value.start_with?('"') && value.end_with?('"') && value.length >= 2
          value = value[1...-1]
          invalid = value.include?('"')
        else
          invalid = value.match?(/[":;,]/)
        end
        raise ValueError, "Invalid parameter quoting" if invalid || value.match?(/[\r\n]/)

        value.gsub(/\^[n'^]/) do |escape|
          { "^n" => "\n", "^'" => '"', "^^" => "^" }.fetch(escape)
        end
      end

      def encode(value)
        value = validate(value)
        encoded = value.gsub(/\r\n|[\r\n"^]/) do |character|
          case character
          when '"' then "^'"
          when "^" then "^^"
          else "^n"
          end
        end
        encoded.empty? || encoded.match?(/[:;,]/) ? "\"#{encoded}\"" : encoded
      end

      def validate(value)
        value = value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String)
        unless value.is_a?(String) && value.valid_encoding? &&
               !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
          raise ValueError, "Parameter value must be a string without control characters"
        end

        value
      end
      private_class_method :validate
    end
  end
end
