# frozen_string_literal: true

require "date"

module SieAnalysis
  # Reports for one parsed financial year. Monetary values are BigDecimal in SEK.
  # Income and monthly summaries use period balances; daily summaries use vouchers.
  class Analysis
    include Amounts
    include IncomeStatements
    include DimensionStatements
    include BalanceSheets
    include Budgets

    CURRENCY = "SEK"
    DIMENSIONS = {
      cost_center: 1,
      project: 6
    }.freeze

    # @param document [Parser::Parsed] a decoded and parsed SIE export
    def initialize(document)
      @parsed = document
    end

    # Summarizes all calendar months touched by the inclusive date range.
    # @param from [Date] first date
    # @param to [Date] last date
    # @param dimension [Symbol, nil] :project or :cost_center
    # @return [Hash] income statement, balance sheet, budget, monthly totals and notes
    def overview(from:, to:, dimension: nil)
      start_date, end_date = from, to
      validate_period!(start_date, end_date)
      months = month_keys(start_date, end_date)
      notes = overview_notes(start_date, end_date)
      dim = require_dimension!(dimension, available_dimensions)
      income = income_statement(months, dim)
      balance = balance_sheet(end_date, months, dim)
      soft_balance_note!(balance, income, notes)
      notes << "Balance sheet totals are omitted when grouping by #{dim}." if dim

      {
        period: { from: start_date, to: end_date },
        currency: CURRENCY,
        granularity: "monthly",
        available_dimensions: available_dimensions,
        income_statement: income,
        budget: budget_overview(months, dim),
        balance_sheet: balance,
        highlights: highlights(income, balance),
        notes:,
        monthly_totals: monthly_totals(months, dim)
      }
    end

    # Lists non-zero monthly movements, optionally filtered by BAS group or object.
    # @param month [String] YYYY-MM
    # @param group_code [String, nil] report group, e.g. "revenue"
    # @param account_number [Integer, nil] BAS account number
    # @param dimension [Symbol, nil] :project or :cost_center
    # @param dimension_code [String, nil] object code; requires dimension
    # @return [Array<Hash>] account_number, account_name, movement and group/object fields
    def account_movements(month:, group_code: nil, account_number: nil, dimension: nil, dimension_code: nil)
      month_label = normalize_year_month(month)
      dim = require_dimension!(dimension, available_dimensions)
      raise ArgumentError, "dimension_code requires dimension" if dimension_code && !dim
      accounts = account_rows_for_month(month_label.delete("-"), dim)
      accounts.select! { |row| row.fetch(:group_code) == group_code } if group_code
      accounts.select! { |row| row.fetch(:account_number) == Integer(account_number) } if account_number
      accounts.select! { |row| row.fetch(:dimension_code) == dimension_code } if dimension_code
      accounts
    end

    # Returns opening balance, movement and closing balance for exactly one period.
    # @param account_number [Integer] BAS account number
    # @param month [String, nil] YYYY-MM; mutually exclusive with on
    # @param on [Date, nil] a single day; requires SIE 4
    # @return [Hash] account fields, Date period boundaries and BigDecimal balances
    def account_summary(account_number, month: nil, on: nil)
      number = Integer(account_number)
      raise ArgumentError, "Provide month or on, not both" if on && month
      return day_account_summary(number, date_argument!(on)) if on
      raise ArgumentError, "month or on is required" unless month

      month_account_summary(number, month)
    end

    # Lists vouchers with a non-zero net movement on the account; requires SIE 4.
    # @param account_number [Integer] BAS account number
    # @param from [Date] inclusive first voucher date
    # @param to [Date] inclusive last voucher date
    # @return [Array<Hash>] series, number, Date, description and BigDecimal movement
    def vouchers_on_account(account_number, from:, to:)
      start_day, end_day = from, to
      require_transactions!
      validate_period!(start_day, end_day)
      number = Integer(account_number)
      @parsed.vouchers.filter_map do |voucher|
        next unless voucher.date.between?(start_day, end_day)

        raw = voucher.lines.sum { |line| line.account == number ? line.amount : BigDecimal("0") }
        next if raw.zero?

        {
          voucher_series: voucher.series,
          voucher_number: voucher.number,
          date: voucher.date,
          description: voucher.description,
          movement: present_ledger_amount(raw, number)
        }
      end
    end

    # @return [Array<Symbol>] supported dimensions with objects declared in the export
    def available_dimensions
      dims = []
      dims << :cost_center if @parsed.objects.keys.any? { |dim, _code| dim == 1 }
      dims << :project if @parsed.objects.keys.any? { |dim, _code| dim == 6 }
      dims
    end

    private

    def date_argument!(date)
      raise ArgumentError, "Expected a Date" unless date.instance_of?(Date)
      date
    end

    def validate_period!(first, last)
      date_argument!(first)
      date_argument!(last)
      raise ArgumentError, "Start date must not be after end date" if first > last
    end

    def require_transactions!
      raise ArgumentError, "This analysis requires a SIE 4 export" unless @parsed.sie_type == 4
    end

    def overview_notes(start_date, end_date)
      notes = ["Amounts use monthly period balances, not day-level bookkeeping."]
      return notes if whole_months?(start_date, end_date)

      notes << "The requested dates are not full calendar months; monthly balances still cover complete months."
      notes
    end

    def month_account_summary(number, year_month)
      month_label = normalize_year_month(year_month)
      start_date = Date.strptime("#{month_label}-01", "%Y-%m-%d")
      end_date = Date.new(start_date.year, start_date.month, -1)
      month_key = month_label.delete("-")
      raw_opening = raw_balance_before_month(number, month_key)
      raw_period = raw_period_amount(number, @parsed.period_changes[month_key] || {})
      build_account_summary(number, start_date, end_date, raw_opening, raw_period)
    end

    def day_account_summary(number, day)
      require_transactions!
      month_start = Date.new(day.year, day.month, 1)
      raw_opening = raw_balance_before_month(number, day.strftime("%Y%m"))
      raw_opening += raw_voucher_amount(number, month_start, day.prev_day) if day.day > 1
      raw_period = raw_voucher_amount(number, day, day)
      build_account_summary(number, day, day, raw_opening, raw_period)
    end

    def build_account_summary(number, start_date, end_date, raw_opening, raw_period)
      {
        account_number: number,
        account_name: @parsed.accounts[number],
        period: { from: start_date, to: end_date },
        movement: present_ledger_amount(raw_period, number),
        opening_balance: present_ledger_amount(raw_opening, number),
        closing_balance: present_ledger_amount(raw_opening + raw_period, number)
      }
    end

    def raw_balance_before_month(account, month_key)
      opening = @parsed.opening_balances[account] || BigDecimal("0")
      prior_months = @parsed.period_changes.keys.select { |key| key < month_key }
      opening + prior_months.sum { |key| raw_period_amount(account, @parsed.period_changes[key] || {}) }
    end

    def raw_voucher_amount(account, start_day, end_day)
      return BigDecimal("0") if end_day < start_day

      @parsed.vouchers.sum do |voucher|
        next BigDecimal("0") unless voucher.date.between?(start_day, end_day)

        voucher.lines.sum { |line| line.account == account ? line.amount : BigDecimal("0") }
      end
    end

    def require_dimension!(dimension, available)
      dim = normalize_dimension(dimension)
      return dim unless dim
      return dim if available.include?(dim)

      raise ArgumentError, "The financial export has no #{dim.to_s.tr('_', ' ')} objects"
    end

    def normalize_dimension(dimension)
      return if dimension.nil?
      raise ArgumentError, "Unsupported dimension" unless DIMENSIONS.key?(dimension)

      dimension
    end

    def normalize_year_month(value)
      text = value.to_s
      raise ArgumentError, "month must be YYYY-MM" unless text.match?(/\A\d{4}-\d{2}\z/)

      Date.strptime("#{text}-01", "%Y-%m-%d")
      text
    rescue Date::Error
      raise ArgumentError, "month must be YYYY-MM"
    end

    def month_keys(start_date, end_date)
      cursor = Date.new(start_date.year, start_date.month, 1)
      last = Date.new(end_date.year, end_date.month, 1)
      keys = []
      while cursor <= last
        keys << cursor.strftime("%Y%m")
        cursor = cursor.next_month
      end
      keys
    end

    def whole_months?(start_date, end_date)
      start_date.day == 1 && end_date == Date.new(end_date.year, end_date.month, -1)
    end
  end
end
