# frozen_string_literal: true

module SieAnalysis
  # Tokenizes one SIE record line, keeping quoted strings and {object lists} intact.
  class SieTokenizer
    def self.tokenize(line)
      new(line).tokens
    end

    def initialize(line)
      @line = line
      @tokens = []
      @buffer = +""
      @in_quotes = false
      @brace_depth = 0
      @index = 0
    end

    def tokens
      consume while @index < @line.length
      flush_buffer
      @tokens
    end

    private

    def consume
      return append_escaped if escaped?
      return toggle_quote if current == '"'
      return handle_structure if !@in_quotes && structural?

      @buffer << current
      @index += 1
    end

    def current
      @line[@index]
    end

    def escaped?
      @in_quotes && current == "\\" && @index + 1 < @line.length
    end

    def structural?
      current == "{" || (current == "}" && @brace_depth.positive?) ||
        (@brace_depth.zero? && current.match?(/\s/))
    end

    def handle_structure
      return open_brace if current == "{"
      return close_brace if current == "}"

      split_token
    end

    def append_escaped
      @buffer << @line[@index + 1]
      @index += 2
    end

    def toggle_quote
      if @in_quotes
        close_quote
      else
        @in_quotes = true
        @buffer << '"' if @brace_depth.positive?
      end
      @index += 1
    end

    def close_quote
      @in_quotes = false
      if @brace_depth.positive?
        @buffer << '"'
      elsif @buffer.empty?
        @tokens << ""
      end
    end

    def open_brace
      @brace_depth += 1
      @buffer << "{"
      @index += 1
    end

    def close_brace
      @brace_depth -= 1
      @buffer << "}"
      flush_buffer if @brace_depth.zero?
      @index += 1
    end

    def split_token
      flush_buffer
      @index += 1
    end

    def flush_buffer
      return if @buffer.empty?

      @tokens << @buffer
      @buffer = +""
    end
  end
end
