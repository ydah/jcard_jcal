# frozen_string_literal: true

module JCardJCal
  # Location-aware failure in a content line or JSON value.
  class Error < StandardError
    attr_reader :line_number, :pointer

    def initialize(message, line_number: nil, pointer: nil)
      @line_number = line_number
      @pointer = pointer
      location = line_number ? "line #{line_number}" : pointer
      super(location ? "#{location}: #{message}" : message)
    end
  end

  class ParseError < Error; end
  class ValidationError < Error; end
  class ValueError < ValidationError; end
  class LimitError < ValueError; end
  class ConversionError < Error; end
end
