# frozen_string_literal: true

module SieAnalysis
  # Balance-sheet builders and closing-balance helpers for Analysis.
  module BalanceSheets
    private

    def balance_sheet(end_date, months, dimension)
      return dimension_balance_placeholder if dimension

      groups = Groups::BALANCE.map { |group| balance_group_row(group, months) }
      assets = group_amount(groups, "assets")
      equity = group_amount(groups, "equity_and_liabilities")
      {
        as_of: end_date,
        assets:,
        equity_and_liabilities: equity,
        cash_and_bank: round_money(cash_total(months)),
        groups: groups.reject { |group| group.fetch(:amount).zero? && group.fetch(:accounts).empty? }
      }
    end

    def group_amount(groups, code)
      groups.find { |row| row[:code] == code }&.fetch(:amount) || BigDecimal("0")
    end

    def cash_total(months)
      balance_accounts_in(Groups::CASH_RANGE).sum do |number|
        present_balance(closing_balance_for(number, months), :asset)
      end
    end

    def balance_group_row(group, months)
      rows = balance_accounts_in(group.fetch(:range)).filter_map do |number|
        presented = present_balance(closing_balance_for(number, months), group.fetch(:kind))
        next if presented.zero?

        { account_number: number, account_name: @parsed.accounts[number], amount: round_money(presented) }
      end
      {
        code: group.fetch(:code),
        label: group.fetch(:label),
        amount: round_money(rows.sum { |row| row.fetch(:amount) }),
        accounts: rows.sort_by { |row| row.fetch(:account_number) }
      }
    end

    def dimension_balance_placeholder
      { as_of: nil, assets: nil, equity_and_liabilities: nil, cash_and_bank: nil, groups: [] }
    end

    def soft_balance_note!(balance, income, notes)
      return if balance[:assets].nil? || balance[:equity_and_liabilities].nil?

      gap = (balance.fetch(:assets) - balance.fetch(:equity_and_liabilities) - income.fetch(:result)).abs
      return if gap < BigDecimal("0.05")

      notes << "Balance sheet assets and equity/liabilities differ after including period result; common mid-year."
    end

    def closing_balance_for(account, months)
      if @parsed.closing_balances.key?(account) && months_cover_year_end?(months)
        return @parsed.closing_balances[account]
      end

      opening = @parsed.opening_balances[account] || BigDecimal("0")
      through_end = @parsed.period_changes.keys.select { |month| month <= months.last }
      opening + through_end.sum { |month| raw_period_amount(account, @parsed.period_changes[month]) }
    end

    def months_cover_year_end?(months)
      rar = @parsed.financial_years[0]
      return false unless rar && rar[:to]

      year_end = Date.strptime(rar[:to].to_s, "%Y%m%d")
      months.include?(year_end.strftime("%Y%m"))
    rescue Date::Error, TypeError
      false
    end

    def balance_accounts_in(range)
      (
        @parsed.accounts.keys + @parsed.opening_balances.keys + @parsed.closing_balances.keys +
          @parsed.period_changes.values.flat_map { |hash| hash.keys.map { |key| dimension_parts(key).first } }
      ).uniq.select { |number| range.cover?(number) }.sort
    end
  end
end
