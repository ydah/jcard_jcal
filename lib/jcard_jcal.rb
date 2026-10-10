# frozen_string_literal: true

require_relative "jcard_jcal/version"
require "json"

module JcardJcal
end

JCardJCal = JcardJcal

require_relative "jcard_jcal/errors"
require_relative "jcard_jcal/content_line/text_codec"
require_relative "jcard_jcal/content_line/reader"
require_relative "jcard_jcal/content_line/writer"
require_relative "jcard_jcal/value_types"
require_relative "jcard_jcal/registry"
require_relative "jcard_jcal/property"
require_relative "jcard_jcal/component"
require_relative "jcard_jcal/converter"
require_relative "jcard"
require_relative "jcal"
