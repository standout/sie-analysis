# frozen_string_literal: true

module SieAnalysis
  # BAS income-statement and undimensioned account-row builders for Analysis.
  module IncomeStatements
    private

    def income_statement(months, dimension)
      dimension ? dimension_income_groups(months, dimension) : bas_income_groups(months)
    end

    def bas_income_groups(months)
      groups = Groups::INCOME.map { |group| bas_group_row(months, group) }
      revenue = sum_kind(groups, :revenue)
      expenses = sum_kind(groups, :expense)
      {
        revenue: round_money(revenue),
        expenses: round_money(expenses),
        result: round_money(revenue - expenses),
        groups: groups.reject { |group| group.fetch(:amount).zero? && group.fetch(:accounts).empty? }
      }
    end

    def bas_group_row(months, group)
      rows = account_amounts_for_range(months, group.fetch(:range), group.fetch(:kind))
      {
        code: group.fetch(:code),
        label: group.fetch(:label),
        amount: round_money(rows.sum { |row| row.fetch(:amount) }),
        accounts: rows.reject { |row| row.fetch(:amount).zero? }
      }
    end

    def sum_kind(groups, kind)
      selected = groups.select do |row|
        Groups::INCOME.find { |definition| definition[:code] == row[:code] }[:kind] == kind
      end
      selected.sum { |row| row.fetch(:amount) }
    end

    def account_rows_for_month(month, dimension)
      return dimension_account_rows(month, dimension) if dimension

      amounts = Hash.new(BigDecimal("0"))
      (@parsed.period_changes[month] || {}).each do |key, raw|
        account, dim, code = dimension_parts(key)
        next if dim || code

        group = Groups.for_account(account)
        next unless group

        amounts[account] += presented_period(raw, group)
      end
      amounts.filter_map { |number, amount| account_row(number, amount) unless amount.zero? }
             .sort_by { |row| row.fetch(:account_number) }
    end

    def presented_period(raw, group)
      income_group?(group) ? present_amount(raw, group.fetch(:kind)) : present_balance(raw, group.fetch(:kind))
    end

    def account_row(number, amount)
      group = Groups.for_account(number)
      {
        account_number: number,
        account_name: @parsed.accounts[number],
        group_code: group&.fetch(:code),
        movement: round_money(amount),
        dimension_code: nil, dimension_label: nil
      }
    end

    def account_amounts_for_range(months, range, kind)
      totals = Hash.new(BigDecimal("0"))
      months.each do |month|
        (@parsed.period_changes[month] || {}).each do |key, raw|
          account, dim, code = dimension_parts(key)
          next if dim || code
          next unless range.cover?(account)

          totals[account] += present_amount(raw, kind)
        end
      end
      totals.map { |number, amount| { account_number: number, account_name: @parsed.accounts[number], amount: round_money(amount) } }
            .sort_by { |row| row.fetch(:account_number) }
    end

    def monthly_totals(months, dimension)
      return if months.length <= 1

      months.map do |month|
        income = income_statement([month], dimension)
        {
          month: "#{month[0, 4]}-#{month[4, 2]}",
          revenue: income.fetch(:revenue),
          expenses: income.fetch(:expenses),
          result: income.fetch(:result)
        }
      end
    end

    def highlights(income, balance)
      revenue = income.fetch(:revenue)
      result = income.fetch(:result)
      margin = revenue.zero? ? nil : round_money((result / revenue) * 100)
      { result:, profit_margin_percent: margin, cash_and_bank: balance[:cash_and_bank] }.compact
    end
  end
end
