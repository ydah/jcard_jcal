# frozen_string_literal: true

require "date"
require "uri"
require_relative "errors"
require_relative "content_line/text_codec"

module JCardJCal
  # Converts scalar property values; structured properties are handled by the converters.
  module ValueTypes
    TYPES = %w[text uri cal-address date time date-time date-and-or-time timestamp boolean integer float
               utc-offset language-tag duration period recur binary unknown].freeze
    MAX_BINARY_SIZE = 1_048_576
    WEEKDAYS = %w[MO TU WE TH FR SA SU].freeze
    FREQUENCIES = %w[SECONDLY MINUTELY HOURLY DAILY WEEKLY MONTHLY YEARLY].freeze
    NUMERIC_RULES = %w[count interval bysecond byminute byhour bymonthday byyearday byweekno bymonth bysetpos].freeze
    RULES = (NUMERIC_RULES + %w[freq until byday wkst rscale skip]).freeze
    DURATION = /\A[+-]?P(?:\d+W|\d+D(?:T(?:\d+H(?:\d+M(?:\d+S)?)?|\d+M(?:\d+S)?|\d+S))?|T(?:\d+H(?:\d+M(?:\d+S)?)?|\d+M(?:\d+S)?|\d+S))\z/i
    GRANDFATHERED_LANGUAGES = %w[en-gb-oed i-ami i-bnn i-default i-enochian i-hak i-klingon i-lux
                                 i-mingo i-navajo i-pwn i-tao i-tay i-tsu sgn-be-fr sgn-be-nl sgn-ch-de
                                 art-lojban cel-gaulish no-bok no-nyn zh-guoyu zh-hakka zh-min zh-min-nan zh-xiang].freeze

    module_function

    def from_text(value, type, format: :vcard, max_binary_size: MAX_BINARY_SIZE)
      string!(value)
      type = type.to_s.downcase
      converted = case type
                  when "text" then ContentLine::TextCodec.decode(value)
                  when "uri", "cal-address" then format == :vcard ? value.gsub("\\,", ",") : value
                  when "boolean"
                    invalid!(type) unless /\A(?:TRUE|FALSE)\z/i.match?(value)
                    value.casecmp?("TRUE")
                  when "integer"
                    invalid!(type) unless /\A[+-]?\d+\z/.match?(value)
                    value.to_i
                  when "float"
                    invalid!(type) unless /\A[+-]?\d+(?:\.\d+)?\z/.match?(value)
                    value.to_f
                  when "date", "time", "date-time", "date-and-or-time", "timestamp", "utc-offset"
                    temporal(value, type, format, true)
                  when "period"
                    value.split("/", -1).map.with_index do |part, i|
                      i == 1 && /\A[+-]?P/i.match?(part) ? part : temporal(part, "date-time", :ical, true)
                    end
                  when "recur" then parse_recur(value)
                  else value
                  end
      from_json(converted, type, format: format, max_binary_size: max_binary_size)
    end

    def from_json(value, type, format: :vcard, max_binary_size: MAX_BINARY_SIZE)
      raise ArgumentError, "format must be :vcard or :ical" unless %i[vcard ical].include?(format)

      type = type.to_s.downcase
      case type
      when "boolean"
        invalid!(type) unless [true, false].include?(value)
      when "integer", "float"
        invalid!(type) unless (value.is_a?(Integer) || value.is_a?(Float)) && value.finite?
        invalid!(type) if type == "integer" && format == :ical && !(value == value.to_i && (-2_147_483_648..2_147_483_647).cover?(value))
      when "period" then validate_period(value)
      when "recur" then validate_recur(value)
      else
        string!(value)
        invalid!(type) if value.match?(/[\x00-\x08\x0b-\x1f\x7f]/) || (type != "text" && value.include?("\n"))
        case type
        when "date", "time", "date-time", "date-and-or-time", "timestamp", "utc-offset"
          temporal(value, type, format, false)
        when "uri", "cal-address" then validate_uri(value)
        when "language-tag" then validate_language(value)
        when "duration" then invalid!(type) unless DURATION.match?(value)
        when "binary" then validate_binary(value, max_binary_size)
        end
      end
      value
    end

    def to_json(value, type, **)
      from_json(value, type, **)
    end

    def to_text(value, type, format: :vcard, max_binary_size: MAX_BINARY_SIZE)
      type = type.to_s.downcase
      from_json(value, type, format: format, max_binary_size: max_binary_size)
      case type
      when "text" then ContentLine::TextCodec.encode(value)
      when "uri", "cal-address" then format == :vcard ? value.gsub(",") { "\\," } : value
      when "boolean" then value ? "TRUE" : "FALSE"
      when "integer" then value.to_i.to_s
      when "float" then decimal(value)
      when "date", "time", "date-time", "date-and-or-time", "timestamp", "utc-offset"
        temporal(value, type, format, false)
      when "period"
        value.map.with_index do |part, i|
          i == 1 && /\A[+]?P/i.match?(part) ? part : temporal(part, "date-time", :ical, false)
        end.join("/")
      when "recur"
        value.map do |key, part|
          part = temporal(part, part.include?("T") ? "date-time" : "date", :ical, false) if key == "until"
          parts = Array(part).map { |item| NUMERIC_RULES.include?(key) && item.is_a?(Numeric) ? item.to_i : item }
          "#{key.upcase}=#{parts.join(",")}"
        end.join(";")
      else value
      end
    end

    def temporal(value, type, format, to_json)
      case type
      when "date" then date(value, format, to_json)
      when "time" then time(value, format, to_json)
      when "utc-offset" then offset(value, format, to_json)
      when "date-and-or-time"
        if value.start_with?("T")
          "T#{time(value[1..], format, to_json)}"
        elsif value.include?("T")
          temporal(value, "date-time", format, to_json)
        else
          date(value, format, to_json)
        end
      else
        parts = value.split("T", -1)
        invalid!(type) unless parts.length == 2
        day, clock = parts
        full = type == "timestamp" || format == :ical
        converted_date = date(day, format, to_json, full: full, no_reduced: true)
        converted_time = time(clock, format, to_json, full: full, no_truncated: true)
        "#{converted_date}T#{converted_time}"
      end
    end

    def date(value, format, to_json, full: false, no_reduced: false)
      expression = to_json ? /\A(?:(\d{4})(\d{2})(\d{2})|--(\d{2})(\d{2}))\z/ : /\A(?:(\d{4})-(\d{2})-(\d{2})|--(\d{2})-(\d{2}))\z/
      match = expression.match(value)
      if match
        year, month, day = match[1] ? match.captures[0, 3] : [nil, match[4], match[5]]
        invalid!("date") if (full || format == :ical) && year.nil?
        invalid!("date") unless Date.valid_date?((year || "2000").to_i, month.to_i, day.to_i, Date::GREGORIAN)
        prefix = year || "--"
        return to_json ? "#{prefix}#{"-" if year}#{month}-#{day}" : "#{prefix}#{month}#{day}"
      end
      invalid!("date") if full || format == :ical
      case value
      when /\A---(\d{2})\z/
        invalid!("date") unless (1..31).cover?(Regexp.last_match(1).to_i)
      when /\A(?:\d{4}-|--)(\d{2})\z/
        invalid!("date") if no_reduced || !(1..12).cover?(Regexp.last_match(1).to_i)
      when /\A\d{4}\z/ then invalid!("date") if no_reduced
      else invalid!("date")
      end
      value
    end

    def time(value, format, to_json, full: false, no_truncated: false)
      expression = if to_json
                     /\A(\d{2}(?:\d{2}){0,2}|-\d{2}(?:\d{2})?|--\d{2})(Z|[+-]\d{2}(?:\d{2})?)?\z/
                   else
                     /\A(\d{2}(?::\d{2}){0,2}|-\d{2}(?::\d{2})?|--\d{2})(Z|[+-]\d{2}(?::\d{2})?)?\z/
                   end
      match = expression.match(value)
      invalid!("time") unless match
      clock, zone = match.captures
      prefix = clock[/\A-*/]
      units = clock.delete(":-").scan(/../).map(&:to_i)
      invalid!("time") if (full || format == :ical) && (units.length != 3 || !prefix.empty?)
      invalid!("time") if no_truncated && !prefix.empty?
      limits = [23, 59, 60].drop(prefix.length)
      invalid!("time") unless units.each_with_index.all? { |unit, i| unit <= limits[i] }
      if zone && zone != "Z"
        invalid!("time") if format == :ical
        zone = offset(zone, :vcard, to_json)
      end
      "#{prefix}#{units.map { |unit| unit.to_s.rjust(2, "0") }.join(to_json ? ":" : "")}#{zone}"
    end

    def offset(value, format, to_json)
      expression = to_json ? /\A([+-])(\d{2})(\d{2})?(\d{2})?\z/ : /\A([+-])(\d{2})(?::(\d{2}))?(?::(\d{2}))?\z/
      match = expression.match(value)
      invalid!("utc-offset") unless match
      sign, hour, minute, second = match.captures
      invalid!("utc-offset") if hour.to_i > 23 || minute.to_i > 59 || second.to_i > 59
      invalid!("utc-offset") if format == :vcard && second
      invalid!("utc-offset") if format == :ical && (!minute || (sign == "-" && [hour, minute, second].all? { |v| v.to_i.zero? }))
      "#{sign}#{[hour, minute, second].compact.join(to_json ? ":" : "")}"
    end

    def validate_period(value)
      invalid!("period") unless value.is_a?(Array) && value.length == 2 && value.all?(String)
      value.each { |part| string!(part) }
      start, finish = value
      temporal(start, "date-time", :ical, false)
      if /\A[+-]?P/i.match?(finish)
        invalid!("period duration") unless DURATION.match?(finish) && !finish.start_with?("-") && finish.scan(/\d+/).any? { |n| n.to_i.positive? }
      else
        temporal(finish, "date-time", :ical, false)
        invalid!("period end") if start.end_with?("Z") == finish.end_with?("Z") && finish <= start
      end
    end

    def parse_recur(value)
      value.split(";", -1).each_with_object({}) do |part, result|
        key, data = part.split("=", 2)
        key = key.to_s.downcase
        invalid!("recur") if !data || data.empty? || result.key?(key) || !RULES.include?(key)
        values = data.split(",", -1)
        values.map! do |item|
          if NUMERIC_RULES.include?(key) && !(key == "bymonth" && /\A\d+L\z/i.match?(item))
            invalid!("recur #{key}") unless /\A[+-]?\d+\z/.match?(item)
            item.to_i
          elsif key == "until"
            temporal(item, item.include?("T") ? "date-time" : "date", :ical, true)
          else
            item
          end
        end
        result[key] = values.length == 1 ? values.first : values
      end
    end

    def validate_recur(value)
      invalid!("recur") unless value.is_a?(Hash) && value.keys.all? { |key| RULES.include?(key) }
      invalid!("recur freq") unless value["freq"].is_a?(String) && FREQUENCIES.include?(value["freq"].upcase)
      invalid!("recur count/until") if value.key?("count") && value.key?("until")
      invalid!("recur skip") if value.key?("skip") && !value.key?("rscale")
      value.each do |key, data|
        if key.start_with?("by")
          parts = data.is_a?(Array) ? data : [data]
          invalid!("recur #{key}") if parts.empty?
          parts.each { |part| validate_rule_part(key, part, value) }
        else
          validate_rule_part(key, data, value)
        end
      end
      frequency = value["freq"].upcase
      invalid!("recur bymonthday") if frequency == "WEEKLY" && value.key?("bymonthday")
      invalid!("recur byyearday") if %w[DAILY WEEKLY MONTHLY].include?(frequency) && value.key?("byyearday")
      invalid!("recur byweekno") if frequency != "YEARLY" && value.key?("byweekno")
      invalid!("recur bysetpos") if value.key?("bysetpos") && value.keys.none? { |key| key.start_with?("by") && key != "bysetpos" }
      return unless Array(value["byday"]).any? { |day| /\A[+-]?\d/.match?(day) }

      invalid!("recur byday") unless %w[MONTHLY YEARLY].include?(frequency)
      invalid!("recur byday") if frequency == "YEARLY" && value.key?("byweekno")
    end

    def validate_rule_part(key, part, rule)
      # ponytail: calendar-specific RSCALE ranges need a calendar engine when semantic validation is added.
      scaled = rule.key?("rscale") && !rule["rscale"].to_s.casecmp?("GREGORIAN")
      valid = case key
              when "freq" then part.is_a?(String) && FREQUENCIES.include?(part.upcase)
              when "wkst" then part.is_a?(String) && WEEKDAYS.include?(part.upcase)
              when "rscale" then part.is_a?(String) && /\A[a-z0-9-]+\z/i.match?(part)
              when "skip" then part.is_a?(String) && %w[OMIT BACKWARD FORWARD].include?(part.upcase)
              when "until"
                string!(part)
                temporal(part, part.include?("T") ? "date-time" : "date", :ical, false)
              when "byday"
                match = /\A([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)\z/i.match(part) if part.is_a?(String)
                match && (!match[1] || (1..(scaled ? 99 : 53)).cover?(match[1].to_i.abs))
              when "bymonth"
                if part.is_a?(String)
                  scaled && /\A\d{1,2}L\z/i.match?(part) && part.to_i.positive?
                else
                  integral?(part) && (1..(scaled ? 99 : 12)).cover?(part)
                end
              when "count", "interval" then integral?(part) && part.positive?
              when "bysecond" then integral?(part) && (0..60).cover?(part)
              when "byminute" then integral?(part) && (0..59).cover?(part)
              when "byhour" then integral?(part) && (0..23).cover?(part)
              when "bymonthday" then integral?(part) && (1..(scaled ? 99 : 31)).cover?(part.abs)
              when "byweekno" then integral?(part) && (1..(scaled ? 99 : 53)).cover?(part.abs)
              when "byyearday", "bysetpos" then integral?(part) && (1..(scaled ? 999 : 366)).cover?(part.abs)
              end
      invalid!("recur #{key}") unless valid
    end

    def integral?(value)
      (value.is_a?(Integer) || value.is_a?(Float)) && value.finite? && value == value.to_i
    end

    def validate_uri(value)
      invalid!("uri") unless value.ascii_only? && !value.match?(/%(?![0-9a-f]{2})/i) && URI.parse(value).absolute?
    rescue URI::InvalidURIError
      invalid!("uri")
    end

    def validate_language(value)
      return if GRANDFATHERED_LANGUAGES.include?(value.downcase)
      return if /\Ax(?:-[a-z0-9]{1,8})+\z/i.match?(value)

      pattern = /\A(?:[a-z]{2,3}(?:-[a-z]{3}){0,3}|[a-z]{4}|[a-z]{5,8})
                 (?:-[a-z]{4})?(?:-(?:[a-z]{2}|\d{3}))?(?:-(?:[a-z0-9]{5,8}|\d[a-z0-9]{3}))*
                 (?:-[0-9a-wy-z](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?\z/ix
      invalid!("language-tag") unless pattern.match?(value)
      singletons = value.downcase.split("-").take_while { |part| part != "x" }.select { |part| part.length == 1 }
      invalid!("language-tag") unless singletons.uniq.length == singletons.length
      variants = value.downcase.split("-").drop(1).take_while { |part| part.length != 1 }
                      .grep(/\A(?:[a-z0-9]{5,8}|\d[a-z0-9]{3})\z/)
      invalid!("language-tag") unless variants.uniq.length == variants.length
    end

    def validate_binary(value, limit)
      validate_binary_size(value, limit)
      invalid!("binary") unless %r{\A(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z}.match?(value)
      padding = if value.end_with?("==")
                  2
                else
                  (value.end_with?("=") ? 1 : 0)
                end
      invalid!("binary padding") if padding == 2 && !"AQgw".include?(value[-3])
      invalid!("binary padding") if padding == 1 && !"AEIMQUYcgkosw048".include?(value[-2])
    end

    def validate_binary_size(value, limit)
      raise ArgumentError, "max_binary_size must be a nonnegative integer" unless limit.is_a?(Integer) && limit >= 0
      return unless value.is_a?(String)

      padding = if value.end_with?("==")
                  2
                else
                  (value.end_with?("=") ? 1 : 0)
                end
      return unless value.bytesize > ((limit + 2) / 3) * 4 || ((value.bytesize / 4) * 3) - padding > limit

      raise LimitError, "binary size limit exceeded"
    end

    def decimal(value)
      string = value.to_s
      return string unless string.include?("e")

      mantissa, exponent = string.split("e")
      sign = mantissa.start_with?("-") ? "-" : ""
      whole, fraction = mantissa.delete_prefix("-").split(".")
      digits = whole + fraction.to_s
      point = whole.length + exponent.to_i
      result = if point <= 0
                 "0.#{"0" * -point}#{digits}"
               elsif point >= digits.length
                 digits + ("0" * (point - digits.length))
               else
                 "#{digits[0, point]}.#{digits[point..]}"
               end
      result = result.sub(/0+\z/, "").delete_suffix(".") if result.include?(".")
      sign + result
    end

    def string!(value)
      unless value.is_a?(String) && value.valid_encoding? && value.encoding.ascii_compatible? &&
             value.dup.force_encoding(Encoding::UTF_8).valid_encoding?
        invalid!("string")
      end
    end

    def invalid!(type)
      raise ValueError, "invalid #{type} value"
    end
  end
end
