# frozen_string_literal: true

require_relative "jcard_jcal"

module JCal
  # An iCalendar property in RFC 7265 array form.
  class Property < JCardJCal::Property
    private

    def default_registry = Registry.default
    def format = :ical
  end

  # An iCalendar component, including vendor components.
  class Component < JCardJCal::Component
    def to_ical = to_text(:ical)
  end

  class Calendar < Component; end

  # Parse one jCal JSON document.
  def self.parse(source, **)
    JCardJCal::Converter.new(format: :ical, **).parse_json(source)
  end

  # Convert a VCALENDAR text document and its nested components.
  def self.from_ical(source, **)
    JCardJCal::Converter.new(format: :ical, **).parse_text(source)
  end
end
