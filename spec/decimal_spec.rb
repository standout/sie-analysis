# frozen_string_literal: true

RSpec.describe "Decimal amounts and Ruby API" do
  def analysis(*rows)
    SieAnalysis::Analysis.new(SieAnalysis::Parser.parse(
      (["#SIETYP 2", "#RAR 0 20240101 20241231"] + rows).join("\n")
    ))
  end

  it "preserves cents beyond Float precision" do
    report = analysis("#PSALDO 0 202401 3010 {} -90071992547409.93")
    expect(report.account_summary(3010, month: "2024-01")[:movement])
      .to eql(BigDecimal("90071992547409.93"))
  end

  it "sums decimal fractions exactly for actuals and budgets" do
    report = analysis("#PSALDO 0 202401 3010 {} -0.1", "#PSALDO 0 202401 3010 {} -0.2",
                      "#PBUDGET 0 202401 3010 {} -0.3")
      .overview(from: Date.new(2024, 1, 1), to: Date.new(2024, 1, 31))
    expect(report[:budget][:rows].first).to include(
      actual: BigDecimal("0.3"), budget: BigDecimal("0.3"), variance: BigDecimal("0")
    )
  end

  it "rounds positive and negative halfway amounts away from zero" do
    report = analysis("#PSALDO 0 202401 4010 {} 1.005", "#PSALDO 0 202401 4020 {} -1.005")
    expect(report.account_summary(4010, month: "2024-01")[:movement]).to eql(BigDecimal("1.01"))
    expect(report.account_summary(4020, month: "2024-01")[:movement]).to eql(BigDecimal("-1.01"))
    expect(report.account_summary(4030, month: "2024-01")[:movement]).to eql(BigDecimal("0"))
  end

  it "requires Date boundaries and exactly one summary period" do
    expect { analysis.overview(from: "2024-01-01", to: Date.new(2024, 1, 31)) }.to raise_error(ArgumentError)
    expect { analysis.account_summary(3010, month: "2024-01", on: Date.new(2024, 1, 1)) }
      .to raise_error(ArgumentError)
  end

  it "filters BAS groups and dimension codes independently" do
    report = SieAnalysis::Analysis.new(SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type3_sample.se")))
    rows = report.account_movements(month: "2024-01", dimension: :cost_center,
                                   dimension_code: "ABC", group_code: "revenue", account_number: 3010)
    expect(rows.length).to eq(1)
    expect(rows.first).to include(group_code: "revenue", dimension_code: "ABC", movement: BigDecimal("50000"))
    expect { report.account_movements(month: "2024-01", dimension_code: "ABC") }.to raise_error(ArgumentError)
    expect { report.account_movements(month: "2024-01", dimension: "project") }.to raise_error(ArgumentError)
  end
end
