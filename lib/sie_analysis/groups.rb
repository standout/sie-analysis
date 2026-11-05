# frozen_string_literal: true

module SieAnalysis
  module Groups
    INCOME = [
      { code: "revenue", label: "Revenue", range: 3000..3999, kind: :revenue },
      { code: "cost_of_goods", label: "Cost of goods sold", range: 4000..4999, kind: :expense },
      { code: "external_costs", label: "External costs", range: 5000..6999, kind: :expense },
      { code: "personnel_costs", label: "Personnel costs", range: 7000..7699, kind: :expense },
      { code: "depreciation", label: "Depreciation", range: 7700..7899, kind: :expense },
      { code: "other_operating", label: "Other operating items", range: 7900..7999, kind: :expense },
      { code: "financial_income", label: "Financial income", range: 8000..8399, kind: :revenue },
      { code: "financial_expenses", label: "Financial expenses", range: 8400..8799, kind: :expense },
      { code: "appropriations_tax", label: "Appropriations and tax", range: 8800..8999, kind: :expense }
    ].freeze

    BALANCE = [
      { code: "assets", label: "Assets", range: 1000..1999, kind: :asset },
      { code: "equity_and_liabilities", label: "Equity and liabilities", range: 2000..2999, kind: :equity_liability }
    ].freeze

    CASH_RANGE = 1910..1999

    def self.for_account(number)
      (INCOME + BALANCE).find { |group| group.fetch(:range).cover?(number) }
    end
  end
end
