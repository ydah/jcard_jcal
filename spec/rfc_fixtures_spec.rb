# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "open3"
require "rubygems/package"
require_relative "../script/prepare_rfc_fixtures"

RSpec.describe RFCFixtures do
  around do |example|
    Dir.mktmpdir("rfc-fetch") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "source.txt") }
  let(:source) { { "url" => "https://www.rfc-editor.org/rfc/rfc7095.txt", "sha256" => Digest::SHA256.hexdigest("test source") } }

  it "downloads once and verifies the cached source on later runs" do
    expect(described_class).to receive(:system).once do |*arguments|
      expect(arguments).to include(source.fetch("url"), "--fail", "--proto", "=https")
      File.binwrite(arguments.last, "test source")
      true
    end
    2.times { described_class.fetch(source, path) }
    expect(File.binread(path)).to eq("test source")
  end

  it "rejects modified cache entries without silently replacing them" do
    File.binwrite(path, "changed source")
    expect(described_class).not_to receive(:system)
    expect { described_class.fetch(source, path) }.to raise_error(/SHA-256 mismatch/)
  end

  it "does not cache an incomplete download" do
    allow(described_class).to receive(:system) do |*arguments|
      File.binwrite(arguments.last, "partial source")
      false
    end
    expect { described_class.fetch(source, path) }.to raise_error(/Download failed/)
    expect(Dir.children(@directory)).to be_empty
  end

  it "rejects a successful response with unexpected content" do
    allow(described_class).to receive(:system) do |*arguments|
      File.binwrite(arguments.last, "unexpected source")
      true
    end
    expect { described_class.fetch(source, path) }.to raise_error(/SHA-256 mismatch/)
    expect(Dir.children(@directory)).to be_empty
  end

  it "rejects missing or changed examples against the pinned corpus fingerprint" do
    expect { described_class.verify_fixtures(@directory) }.to raise_error(/Fixture fingerprint mismatch/)
    File.write(File.join(@directory, "manifest.json"), "[]\n")
    expect { described_class.verify_fixtures(@directory) }.to raise_error(/Fixture fingerprint mismatch/)
    expect { described_class.verify_fixtures(described_class::DIRECTORY) }.not_to raise_error
  end

  it "generates the complete corpus with attribution using only verified cached sources" do
    FileUtils.cp_r(File.join(described_class::ROOT, "sources"), @directory)
    stub_const("RFCFixtures::ROOT", @directory)
    stub_const("RFCFixtures::DIRECTORY", File.join(@directory, "fixtures"))
    expect(described_class).not_to receive(:system)
    expect { described_class.prepare }.to output(/Extracted 144 examples/).to_stdout
    expect { described_class.verify_fixtures(described_class::DIRECTORY) }.not_to raise_error
    notice = File.read(File.join(described_class::DIRECTORY, "LICENSE"))
    expect(notice).to include("Revised BSD License", "IETF Trust", "https://trustee.ietf.org/license-info")
  end

  it "builds an MIT gem without downloaded sources, fixtures, or development dependencies" do
    gem_path = File.join(@directory, "jcard_jcal.gem")
    output, status = Open3.capture2e("gem", "build", "--strict", "jcard_jcal.gemspec", "--output", gem_path)
    expect(status.success?).to be(true), output
    package = Gem::Package.new(gem_path)
    expect(package.spec.licenses).to eq(["MIT"])
    expect(package.contents.grep(%r{\A(?:tmp|test|spec|script|node_modules|data/iana)/})).to be_empty
    expect(package.spec.dependencies.select { |dependency| dependency.type == :runtime }.map(&:name)).to eq(["json"])
  end
end
