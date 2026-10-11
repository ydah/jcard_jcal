# frozen_string_literal: true

module JCardJCal
  module ContentLine
    # Escaping for TEXT property values (RFC 5545 section 3.3.11).
    module TextCodec
      module_function

      def decode(value)
        value = validate(value)
        value.gsub(/\\([\\,;nN])|\\(.)|\\\z/m) do
          escaped = Regexp.last_match(1)
          raise ValueError, "Invalid TEXT escape" unless escaped

          %w[n N].include?(escaped) ? "\n" : escaped
        end
      end

      def encode(value)
        value = validate(value)
        value.gsub(/\r\n|[\r\n\\,;]/) do |character|
          ["\r\n", "\r", "\n"].include?(character) ? '\n' : "\\#{character}"
        end
      end

      # Split before decoding so escaped list and field separators remain data.
      def split(value, delimiter)
        value = validate(value)
        raise ArgumentError, "delimiter must be one character" unless delimiter.is_a?(String) && delimiter.length == 1

        parts = [String.new]
        escaped = false
        value.each_char do |character|
          if character == delimiter && !escaped
            parts << String.new
          else
            parts.last << character
          end
          escaped = character == "\\" && !escaped
        end
        parts
      end

      def validate(value)
        value = value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String)
        unless value.is_a?(String) && value.valid_encoding? &&
               !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
          raise ValueError, "TEXT value must be a string without control characters"
        end

        value
      end
      private_class_method :validate
    end
  end
end
