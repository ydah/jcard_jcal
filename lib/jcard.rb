# frozen_string_literal: true

require_relative "jcard_jcal"

module JCard
  # A vCard property in RFC 7095 array form.
  class Property < JCardJCal::Property
    private

    def default_registry = Registry.default
    def format = :vcard
  end

  # A vCard 4.0 represented as jCard.
  class Card < JCardJCal::Component
    def to_vcard = to_text(:vcard)
  end

  # Parse one jCard JSON document. Lenient parsing attaches validation warnings.
  def self.parse(source, **)
    JCardJCal::Converter.new(format: :vcard, **).parse_json(source)
  end

  # Convert one or more vCards to ordered card objects.
  def self.from_vcard(source, **)
    JCardJCal::Converter.new(format: :vcard, **).parse_text(source)
  end
end
