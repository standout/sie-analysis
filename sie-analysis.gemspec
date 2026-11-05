# frozen_string_literal: true

require_relative "lib/sie_analysis/version"

Gem::Specification.new do |spec|
  spec.name = "sie-analysis"
  spec.version = SieAnalysis::VERSION
  spec.authors = ["Standout AB"]
  spec.summary = "Income statements, account movements and budget analysis for SIE exports"
  spec.homepage = "https://github.com/standout/sie-analysis"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "README.md", "assets/*"]
  spec.add_dependency "bigdecimal", ">= 3.1", "< 5"
  spec.require_paths = ["lib"]
end
