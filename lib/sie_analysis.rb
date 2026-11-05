# frozen_string_literal: true

require "bigdecimal"
require_relative "sie_analysis/version"

# Analysis of Swedish SIE financial exports.
module SieAnalysis
  # A malformed or unsupported SIE export.
  class ParseError < StandardError; end
end

require_relative "sie_analysis/groups"
require_relative "sie_analysis/sie_tokenizer"
require_relative "sie_analysis/parser"
require_relative "sie_analysis/amounts"
require_relative "sie_analysis/budgets"
require_relative "sie_analysis/income_statements"
require_relative "sie_analysis/dimension_statements"
require_relative "sie_analysis/balance_sheets"
require_relative "sie_analysis/analysis"
