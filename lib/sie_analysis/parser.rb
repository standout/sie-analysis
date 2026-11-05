# frozen_string_literal: true

require "date"

module SieAnalysis
  # Parses financial export types 2–4 into balances and (for type 4) voucher lines.
  class Parser
    Record = Data.define(:tag, :fields)
    Voucher = Data.define(:series, :number, :date, :description, :lines)
    # Voucher line with [dimension number, object code] references.
    Line = Data.define(:account, :amount, :objects)

    # Parsed ledger: monetary values are BigDecimal; voucher dates are Date.
    # Period keys are YYYYMM strings; object keys are [dimension number, code].
    # Dimensions maps declared dimension numbers to their exported names.
    Parsed = Data.define(
      :accounts, :objects, :opening_balances, :closing_balances, :results, :period_changes,
      :financial_years, :vouchers, :budgets, :sie_type, :dimensions
    )

    # @param text [String] export text already decoded to UTF-8
    # @return [Parsed] recognized balances, objects, budgets and vouchers
    # @raise [ParseError] invalid export type, financial year or recognized record
    def self.parse(text)
      new(text).parse
    end

    # @param text [String] decoded SIE 2, 3 or 4 text
    def initialize(text)
      @text = text.to_s
      @accounts = {}
      @objects = {}
      @dimensions = {}
      @opening = Hash.new(BigDecimal("0"))
      @closing = Hash.new(BigDecimal("0"))
      @results = Hash.new(BigDecimal("0"))
      @periods = Hash.new { |hash, key| hash[key] = Hash.new(BigDecimal("0")) }
      @budgets = Hash.new { |hash, key| hash[key] = Hash.new(BigDecimal("0")) }
      @years = {}
      @vouchers = []
      @current_voucher = nil
    end

    # Consumes this parser once. Use .parse for each separate export.
    # @return [Parsed] parsed ledger
    # @raise [ParseError] unreadable or invalid recognized records
    def parse
      each_record { |record| apply_record(record) }
      finish_voucher!
      raise ArgumentError unless [2, 3, 4].include?(@sie_type) && @years.key?(0)
      @periods.default_proc = nil
      @budgets.default_proc = nil
      Parsed.new(
        accounts: @accounts, objects: @objects, opening_balances: @opening, closing_balances: @closing,
        results: @results, period_changes: @periods, financial_years: @years, vouchers: @vouchers,
        budgets: @budgets, sie_type: @sie_type, dimensions: @dimensions
      )
    rescue ParseError
      raise
    rescue StandardError
      raise ParseError, "Unreadable financial export"
    end

    private

    def each_record
      @text.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || !stripped.start_with?("#")

        tokens = SieTokenizer.tokenize(stripped[1..])
        next if tokens.empty?

        yield Record.new(tag: tokens[0], fields: tokens[1..])
      end
    end

    def apply_record(record)
      case record.tag
      when "SIETYP"
        raise ArgumentError if @sie_type
        @sie_type = Integer(record.fields.fetch(0))
      when "KONTO" then apply_account(record.fields)
      when "OBJEKT" then apply_object(record.fields)
      when "DIM", "UNDERDIM" then apply_dimension(record.fields)
      when "RAR" then apply_year(record.fields)
      when "IB" then apply_balance!(@opening, record.fields)
      when "UB" then apply_balance!(@closing, record.fields)
      when "RES" then apply_balance!(@results, record.fields)
      when "PSALDO" then apply_period!(record.fields)
      when "PBUDGET" then apply_budget!(record.fields)
      when "VER" then start_voucher!(record.fields)
      when "TRANS" then apply_trans!(record.fields)
      end
    end

    def apply_account(fields)
      number = integer_field(fields[0])
      @accounts[number] = unquote(fields[1]).to_s if number
    end

    def apply_object(fields)
      dim = integer_field(fields[0])
      code = unquote(fields[1]).to_s
      name = unquote(fields[2]).to_s
      @objects[[dim, code]] = name if dim && !code.empty?
    end

    def apply_dimension(fields)
      number = integer_field(fields[0])
      raise ArgumentError unless number&.positive?

      @dimensions[number] = unquote(fields.fetch(1))
    end

    def apply_year(fields)
      year_no = integer_field(fields[0])
      first, last = sie_date(fields[1]), sie_date(fields[2])
      raise ArgumentError unless year_no && first && last && first <= last
      raise ArgumentError if @years.key?(year_no)
      @years[year_no] = { from: unquote(fields[1]), to: unquote(fields[2]) }
    end

    def apply_balance!(target, fields)
      year = integer_field(fields[0])
      raise ArgumentError unless year
      return unless year.zero?

      account = integer_field(fields[1])
      amount = decimal_field(fields[2])
      raise ArgumentError unless account&.positive? && amount&.finite?

      target[account] += amount
    end

    def apply_period!(fields, target = @periods)
      year = integer_field(fields[0])
      raise ArgumentError unless year
      return unless year.zero?

      period = fields[1].to_s
      account = integer_field(fields[2])
      object_field = fields[3].to_s
      amount = object_field.start_with?("{") ? decimal_field(fields[4]) : decimal_field(fields[3])
      raise ArgumentError unless period.match?(/\A\d{4}(0[1-9]|1[0-2])\z/) && account&.positive? && amount&.finite?
      raise ArgumentError if object_field.start_with?("{") && !valid_budget_objects?(object_field)

      refs = object_refs_from(object_field)
      if refs.empty?
        target[period][account] += amount
      else
        refs.each { |dim, code| target[period][[account, dim, code]] += amount }
      end
    end

    def apply_budget!(fields)
      year = integer_field(fields[0])
      raise ArgumentError unless year
      return unless year.zero?

      period, account, objects, amount = fields.values_at(1, 2, 3, 4)
      raise ArgumentError unless period.to_s.match?(/\A\d{4}(0[1-9]|1[0-2])\z/)
      raise ArgumentError unless integer_field(account)&.positive? && decimal_field(amount)&.finite?
      raise ArgumentError unless valid_budget_objects?(objects)

      apply_period!(fields, @budgets)
    end

    def valid_budget_objects?(objects)
      return false unless objects.to_s.start_with?("{") && objects.end_with?("}")

      parts = SieTokenizer.tokenize(objects[1...-1])
      parts.length.even? && parts.each_slice(2).all? do |dim, code|
        integer_field(dim)&.positive? && !unquote(code).empty?
      end
    end

    def start_voucher!(fields)
      finish_voucher!
      date = sie_date(fields[2])
      number = integer_field(fields[1])
      raise ArgumentError unless date && number

      @current_voucher = {
        series: unquote(fields[0]).to_s,
        number:,
        date:,
        description: unquote(fields[3]).to_s,
        lines: []
      }
    end

    def apply_trans!(fields)
      raise ArgumentError unless @current_voucher

      account = integer_field(fields[0])
      object_field = fields[1].to_s
      amount = object_field.start_with?("{") ? decimal_field(fields[2]) : decimal_field(fields[1])
      raise ArgumentError unless account&.positive? && amount&.finite?

      raise ArgumentError if object_field.start_with?("{") && !valid_budget_objects?(object_field)

      @current_voucher[:lines] << Line.new(account:, amount:, objects: object_refs_from(object_field))
    end

    def finish_voucher!
      voucher = @current_voucher
      @current_voucher = nil
      return unless voucher && voucher[:lines].any?

      @vouchers << Voucher.new(
        series: voucher[:series], number: voucher[:number], date: voucher[:date],
        description: voucher[:description], lines: voucher[:lines]
      )
    end

    def object_refs_from(field)
      text = field.to_s
      return [] unless text.start_with?("{") && text.end_with?("}")

      inner = text[1...-1].strip
      return [] if inner.empty?

      parts = SieTokenizer.tokenize(inner)
      parts.each_slice(2).filter_map do |dim_token, code_token|
        dim = integer_field(dim_token)
        code = unquote(code_token).to_s
        [dim, code] if dim && !code.empty?
      end
    end

    def sie_date(value)
      text = unquote(value).to_s
      return unless text.match?(/\A\d{8}\z/)

      Date.strptime(text, "%Y%m%d")
    rescue Date::Error
      nil
    end

    def integer_field(value)
      Integer(unquote(value))
    rescue TypeError, ArgumentError
      nil
    end

    def decimal_field(value)
      text = unquote(value).tr(",", ".")
      return unless text.match?(/\A[+-]?\d+(?:\.\d+)?\z/)
      BigDecimal(text)
    rescue TypeError, ArgumentError
      nil
    end

    def unquote(value)
      text = value.to_s
      return text[1...-1] if text.start_with?('"') && text.end_with?('"') && text.length >= 2

      text
    end
  end
end
