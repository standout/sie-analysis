# frozen_string_literal: true

module SieAnalysis
  # Compare only explicitly exported monthly income budgets with matching ledger rows.
  module Budgets
    private

    def budget_overview(months, dimension)
      rows = months.flat_map do |month|
        (@parsed.budgets[month] || {}).filter_map do |key, raw|
          budget_row(month, key, raw, dimension)
        end
      end
      rows.sort_by! { |row| [row[:month], row[:dimension_code].to_s, row[:account_number]] }
      {
        status: rows.empty? ? "unavailable" : "available",
        rows:
      }
    end

    def budget_row(month, key, raw, dimension)
      account, dim, code = dimension_parts(key)
      return unless dim == (dimension && Analysis::DIMENSIONS.fetch(dimension))

      group = Groups.for_account(account)
      return unless income_group?(group)

      budget = round_money(present_amount(raw, group.fetch(:kind)))
      actual_raw = (@parsed.period_changes[month] || {}).fetch(key, BigDecimal("0"))
      actual = round_money(present_amount(actual_raw, group.fetch(:kind)))
      {
        month: "#{month[0, 4]}-#{month[4, 2]}",
        account_number: account, account_name: @parsed.accounts[account],
        dimension_code: code, dimension_label: code && (@parsed.objects[[dim, code]] || code),
        budget:, actual:, variance: round_money(actual - budget)
      }
    end
  end
end
