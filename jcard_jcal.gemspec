# frozen_string_literal: true

require_relative "lib/jcard_jcal/version"

Gem::Specification.new do |spec|
  spec.name = "jcard_jcal"
  spec.version = JcardJcal::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Convert vCard and iCalendar to and from jCard and jCal"
  spec.description = "Read, validate, and write jCard (RFC 7095) and jCal (RFC 7265), " \
                     "including structured values, recurrence rules, and unknown extensions."
  spec.homepage = "https://github.com/ydah/jcard_jcal"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "sig/**/*.rbs", "data/*.yml", "README.md", "LICENSE.txt", "CHANGELOG.md", "SECURITY.md"] }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "json", ">= 2.19.4", "< 4"
end
