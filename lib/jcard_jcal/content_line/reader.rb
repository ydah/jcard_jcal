# frozen_string_literal: true

require "strscan"
require_relative "param_codec"

module JCardJCal
  module ContentLine
    Line = Struct.new(:name, :group, :params, :value, :line_number, keyword_init: true)

    # Enumerates unfolded lines, reporting the first physical line of each one.
    class Reader
      include Enumerable

      def initialize(text, max_line_length: 1_048_576)
        raise ArgumentError, "text must be a string" unless text.is_a?(String)
        raise ArgumentError, "max_line_length must be a positive integer" unless max_line_length.is_a?(Integer) && max_line_length.positive?

        @text = text
        @max_line_length = max_line_length
      end

      def each
        return enum_for(__method__) unless block_given?

        unfolded = nil
        first_line = nil
        # Unfold bytes before checking UTF-8; peers may split a multibyte character.
        @text.b.each_line.with_index(1) do |physical, number|
          physical.delete_suffix!("\r") if physical.delete_suffix!("\n")
          check_length(physical.bytesize, number)
          if physical.start_with?(" ", "\t")
            fail_line("Continuation without a preceding line", number) unless unfolded
            check_length(unfolded.bytesize + physical.bytesize - 1, first_line)
            unfolded << physical.byteslice(1..)
          else
            yield parse(unfolded, first_line) if unfolded
            unfolded = physical
            first_line = number
          end
        end
        yield parse(unfolded, first_line) if unfolded
        self
      end

      private

      def parse(text, number)
        text.force_encoding(Encoding::UTF_8)
        fail_line("Invalid UTF-8 or control character", number) unless text.valid_encoding? && !text.match?(/[\x00-\x08\x0a-\x1f\x7f]/)

        scanner = StringScanner.new(text)
        name = scanner.scan(/[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)?/)
        fail_line("Invalid property name", number) unless name
        group, name = name.split(".", 2) if name.include?(".")
        params = {}
        while scanner.scan(";")
          key = scanner.scan(/[A-Za-z0-9-]+/)&.downcase
          fail_line("Invalid parameter name or missing equals sign", number) unless key && scanner.scan("=")
          fail_line("Duplicate parameter #{key}", number) if params.key?(key)

          values = []
          loop do
            raw = scanner.peek(1) == '"' ? scanner.scan(/"[^"]*"/) : scanner.scan(/[^":;,]*/)
            fail_line("Invalid parameter quoting", number) unless raw
            values << ParamCodec.decode(raw)
            break unless scanner.scan(",")
          end
          params[key] = values.length == 1 ? values.first : values
        end
        fail_line("Missing colon or malformed parameter", number) unless scanner.scan(":")

        Line.new(name: name.downcase, group: group, params: params, value: scanner.rest, line_number: number)
      rescue ValueError => e
        fail_line(e.message, number)
      end

      def check_length(length, number)
        fail_line("Content line exceeds maximum length of #{@max_line_length} bytes", number) if length > @max_line_length
      end

      def fail_line(message, number)
        raise ParseError.new(message, line_number: number)
      end
    end
  end
end
