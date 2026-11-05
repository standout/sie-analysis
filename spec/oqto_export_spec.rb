# frozen_string_literal: true

RSpec.describe "Oqto period export syntax" do
  it "reads period amounts without an object list and balances with quantities" do
    text = <<~SIE
      #SIETYP 2
      #RAR 0 20260101 20261231
      #OMFATTN 20261103
      #KONTO 1510 "Receivables"
      #KONTO 2611 "VAT"
      #KONTO 3001 "Sales"
      #IB 0 1510 0 0
      #IB 0 2611 0 0
      #UB 0 1510 125.00 0
      #UB 0 2611 -25.00 0
      #PSALDO 0 202611 1510  125.00
      #PSALDO 0 202611 2611  -25.00
      #PSALDO 0 202611 3001  -100
      #RES 0 3001 -100 0
    SIE
    parsed = SieAnalysis::Parser.parse(text)
    expect(parsed.period_changes["202611"]).to eq(1510 => 125.0, 2611 => -25.0, 3001 => -100.0)
    report = SieAnalysis::Analysis.new(parsed).overview(
      from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 3)
    )
    expect(report[:income_statement]).to include(revenue: 100.0, result: 100.0)
    expect(report[:granularity]).to eq("monthly")
    expect(report[:notes]).to include(
      "The requested dates are not full calendar months; monthly balances still cover complete months."
    )
  end
end
