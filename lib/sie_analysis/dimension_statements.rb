# frozen_string_literal: true

module SieAnalysis
  # Income and account-row builders for any SIE dimension.
  module DimensionStatements
    private

    def dimension_income_groups(months, dimension)
      dim_no = dimension_number(dimension)
      totals = accumulate_dimension_totals(months, dim_no)
      groups = dimension_group_rows(totals, dim_no)
      revenue = totals.values.sum { |values| values[:revenue] }
      expenses = totals.values.sum { |values| values[:expenses] }
      {
        revenue: round_money(revenue),
        expenses: round_money(expenses),
        result: round_money(revenue - expenses),
        groups:
      }
    end

    def accumulate_dimension_totals(months, dim_no)
      totals = Hash.new { |hash, key| hash[key] = { revenue: BigDecimal("0"), expenses: BigDecimal("0"), accounts: Hash.new(BigDecimal("0")) } }
      months.each do |month|
        (@parsed.period_changes[month] || {}).each do |key, raw|
          account, dim, code = dimension_parts(key)
          next unless dim == dim_no && code

          group = Groups.for_account(account)
          next unless income_group?(group)

          presented = present_amount(raw, group.fetch(:kind))
          bucket = totals[code]
          bucket[group.fetch(:kind) == :revenue ? :revenue : :expenses] += presented
          bucket[:accounts][account] += presented
        end
      end
      totals
    end

    def dimension_group_rows(totals, dim_no)
      rows = totals.map do |code, values|
        accounts = values[:accounts].filter_map do |number, amount|
          next if amount.zero?

          { account_number: number, account_name: @parsed.accounts[number], amount: round_money(amount) }
        end
        {
          code:,
          label: @parsed.objects[[dim_no, code]] || code,
          amount: round_money(values[:revenue] - values[:expenses]),
          accounts: accounts.sort_by { |row| row.fetch(:account_number) }
        }
      end
      rows.sort_by { |group| group.fetch(:code) }
    end

    def dimension_account_rows(month, dimension)
      dim_no = dimension_number(dimension)
      rows = []
      (@parsed.period_changes[month] || {}).each do |key, raw|
        account, dim, code = dimension_parts(key)
        next unless dim == dim_no && code

        group = Groups.for_account(account)
        next unless group

        presented = presented_period(raw, group)
        next if presented.zero?

        rows << {
          account_number: account,
          account_name: @parsed.accounts[account],
          group_code: group.fetch(:code),
          dimension_code: code,
          movement: round_money(presented),
          dimension_label: @parsed.objects[[dim_no, code]] || code
        }
      end
      rows.sort_by { |row| [row.fetch(:dimension_code), row.fetch(:account_number)] }
    end
  end
end
