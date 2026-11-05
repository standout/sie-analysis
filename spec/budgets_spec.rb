# frozen_string_literal: true

RSpec.describe "Financial overview budgets" do
  let(:fixture) { File.read("spec/fixtures/sie_budget_sample.se") }

  # Live Fortnox SIE2 keeps account-total #PBUDGET only; types 3/4 add object rows.
  def type2_shaped(text)
    text.sub("#SIETYP 3", "#SIETYP 2").lines.reject do |line|
      line.start_with?("#PBUDGET") && !line.match?(/\{\s*\}/)
    end.join
  end

  def overview(text, dimension: nil, from: "2026-09-01", to: "2026-09-30")
    parsed = SieAnalysis::Parser.parse(text)
    SieAnalysis::Analysis.new(parsed).overview(
      from: Date.iso8601(from), to: Date.iso8601(to), dimension:
    )
  end

  it "compares account totals without adding cost center allocations" do
    result = overview(fixture)
    expected = {
      month: "2026-09", account_number: 3001, account_name: "Example sales",
      dimension_code: nil, dimension_label: nil, budget: 15_416.0, actual: 20_000.0, variance: 4584.0
    }
    expect(result[:budget]).to eq(status: "available", rows: [expected])
    expect(result.dig(:income_statement, :revenue)).to eq(20_000.0)
  end

  it "preserves all twelve months and the annual account budget from the manual export" do
    result = overview(fixture, from: "2026-01-01", to: "2026-12-31")
    rows = result.dig(:budget, :rows)
    expect(rows.length).to eq(12)
    expect(rows.sum { |row| row[:budget] }).to eq(185_000.0)
    expect(rows.first).to include(month: "2026-01", budget: 15_418.0, actual: 0.0)
    expect(rows.last).to include(month: "2026-12", budget: 15_416.0)
  end

  it "compares cost centers separately; live Fortnox budgets have no project rows" do
    rows = overview(fixture, dimension: :cost_center).dig(:budget, :rows)
    expect(rows).to contain_exactly(
      include(dimension_code: "123", budget: 2083.0, actual: 2000.0, variance: -83.0),
      include(dimension_code: "ABC", budget: 833.0, actual: 1000.0, variance: 167.0)
    )
    expect(overview(fixture, dimension: :project)[:budget])
      .to eq(status: "unavailable", rows: [])
  end

  it "matches live SIE2 vs SIE3/4 budget shapes" do
    type2 = type2_shaped(fixture)
    expect(type2.scan(/^#PBUDGET /).length).to eq(12)
    expect(overview(type2).dig(:budget, :rows)).to contain_exactly(
      include(account_number: 3001, dimension_code: nil, budget: 15_416.0)
    )
    expect(overview(type2, dimension: :cost_center)[:budget])
      .to eq(status: "unavailable", rows: [])

    expect(fixture.scan(/^#PBUDGET /).length).to eq(36)
    expect(overview(fixture.sub("#SIETYP 3", "#SIETYP 4"))[:budget]).to eq(overview(fixture)[:budget])
  end

  it "retains explicit zero budgets and budget-only accounts with expense signs" do
    text = fixture + <<~SIE
      #PBUDGET 0 202609 4000 {} 1000,50
      #PSALDO 0 202609 4000 {} 1200
      #PBUDGET 0 202609 5000 {} 0
      #PBUDGET 0 202609 6000 {} 500
      #PBUDGET 0 202609 1930 {} 999
    SIE
    rows = overview(text).dig(:budget, :rows)
    expect(rows).to include(include(account_number: 4000, budget: 1000.5, actual: 1200.0, variance: 199.5))
    expect(rows).to include(include(account_number: 5000, account_name: nil, budget: 0.0, actual: 0.0))
    expect(rows).to include(include(account_number: 6000, budget: 500.0, actual: 0.0, variance: -500.0))
    expect(rows.map { |row| row[:account_number] }).not_to include(1930)
  end

  it "does not invent zero budgets for missing months, dimensions, or prior years" do
    text = fixture.lines.reject { |line| line.start_with?("#PBUDGET") }.join
    text += "#PBUDGET -1 202609 3001 {} -999\n#PBUDGET 0 202608 3001 {} -123\n"
    expect(overview(text)[:budget]).to eq(status: "unavailable", rows: [])
    expect(overview("#SIETYP 2\n#RAR 0 20260101 20261231\n")[:budget]).to eq(status: "unavailable", rows: [])
  end

  it "returns all budget rows without truncation" do
    rows = (3000..3599).map { |number| "#PBUDGET 0 202609 #{number} {} -1" }.join("\n")
    result = overview("#SIETYP 2\n#RAR 0 20260101 20261231\n#{rows}")
    expect(result[:budget][:rows].length).to eq(600)
    expect(result[:budget]).not_to have_key(:truncated)
  end

  it "uses complete monthly actual and budget amounts for partial-month requests" do
    result = overview(fixture, from: "2026-09-12", to: "2026-09-15")
    expect(result[:budget]).to eq(overview(fixture)[:budget])
    expect(result[:notes].join).to include("complete months")
  end

  it "rejects malformed budget records without exposing their contents" do
    ["202613 3001 {} -1", "202609 BAD {} -1", "202609 3001 {} secret",
     "202609 3001 {1} -1", "202609 3001 {1 \"\"} -1", "202609 3001 {} 1e999"].each do |fields|
      expect { overview("#SIETYP 2\n#RAR 0 20260101 20261231\n#PBUDGET 0 #{fields}") }.to raise_error(
        SieAnalysis::ParseError, "Unreadable financial export"
      )
    end
  end
end
