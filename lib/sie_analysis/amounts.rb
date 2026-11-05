# frozen_string_literal: true

module SieAnalysis
  # Shared ledger amount presentation helpers for Analysis.
  module Amounts
    private

    # Period keys are either account or [account, dimension_no, object_code].
    def dimension_parts(key)
      case key
      when Array
        account, dim, code = key
        [account, dim, code]
      else
        [key, nil, nil]
      end
    end

    def income_group?(group)
      group && Groups::INCOME.any? { |item| item.equal?(group) }
    end

    def present_amount(raw, kind)
      kind == :revenue ? -raw : raw
    end

    def present_balance(raw, kind)
      kind == :equity_liability ? -raw : raw
    end

    def round_money(value)
      BigDecimal(value.to_s).round(2, BigDecimal::ROUND_HALF_UP)
    end

    def present_ledger_amount(raw, account_number)
      group = Groups.for_account(account_number)
      return round_money(raw) unless group

      presented = if income_group?(group)
                    present_amount(raw, group.fetch(:kind))
                  else
                    present_balance(raw, group.fetch(:kind))
                  end
      round_money(presented)
    end

    def raw_period_amount(account, month_hash)
      month_hash.fetch(account, BigDecimal("0"))
    end
  end
end
