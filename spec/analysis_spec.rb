# frozen_string_literal: true

RSpec.describe SieAnalysis::Analysis do
  subject(:analysis) { described_class.new(parsed) }

  let(:parsed) { SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type2_sample.se")) }

  it "builds an overview with groups, nested accounts, and monthly totals" do
    result = analysis.overview(from: Date.new(2024, 1, 1), to: Date.new(2024, 3, 31))

    expect(result.fetch(:currency)).to eq("SEK")
    expect(result.fetch(:granularity)).to eq("monthly")
    expect(result.fetch(:income_statement).fetch(:revenue)).to eq(300_000.0)
    expect(result.fetch(:income_statement).fetch(:groups).map { |group| group.fetch(:code) }).to include("revenue")
    revenue_group = result.fetch(:income_statement).fetch(:groups).find { |group| group[:code] == "revenue" }
    expect(revenue_group.fetch(:accounts).map { |row| row.fetch(:account_number) }).to include(3010)
    expect(result.fetch(:monthly_totals).length).to eq(3)
    expect(result.fetch(:balance_sheet).fetch(:cash_and_bank)).to be_a(BigDecimal)
  end

  it "includes earlier movements in a mid-year balance sheet but not its income period" do
    result = analysis.overview(from: Date.new(2024, 3, 1), to: Date.new(2024, 3, 31))
    expect(result.dig(:balance_sheet, :cash_and_bank)).to eq(120_000.0)
    expect(result.dig(:balance_sheet, :equity_and_liabilities)).to eq(30_000.0)
    expect(result.dig(:income_statement, :revenue)).to eq(80_000.0)
  end

  it "lists accounts for one month with group codes" do
    result = analysis.account_movements(month: "2024-01")

    row = result.find { |account| account.fetch(:account_number) == 3010 }
    expect(row).to include(group_code: "revenue", movement: 100_000.0)
  end

  it "aggregates cost centers from type 3 data" do
    typed = SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type3_sample.se"))
    result = described_class.new(typed).overview(
      from: Date.new(2024, 1, 1), to: Date.new(2024, 1, 31), dimension: :cost_center
    )

    expect(result.fetch(:available_dimensions)).to eq(%i[cost_center project])
    groups = result.fetch(:income_statement).fetch(:groups)
    expect(groups.map { |group| group.fetch(:code) }).to contain_exactly("ABC", "XYZ")
    abc = groups.find { |group| group.fetch(:code) == "ABC" }
    xyz = groups.find { |group| group.fetch(:code) == "XYZ" }
    # Cost center ABC must not include project ABC amounts that share the same code.
    expect(abc.fetch(:amount)).to eq(30_000.0)
    expect(abc.fetch(:label)).to eq("Avdelning ABC")
    expect(xyz.fetch(:amount)).to eq(25_000.0)
    expect(result.fetch(:income_statement).fetch(:revenue)).to eq(85_000.0)
    expect(result.fetch(:income_statement).fetch(:expenses)).to eq(30_000.0)
    expect(result.fetch(:income_statement).fetch(:result)).to eq(55_000.0)
  end

  it "keeps project totals separate from cost centers with the same object code" do
    typed = SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type3_sample.se"))
    result = described_class.new(typed).overview(
      from: Date.new(2024, 1, 1), to: Date.new(2024, 1, 31), dimension: :project
    )

    groups = result.fetch(:income_statement).fetch(:groups)
    expect(groups.map { |group| group.fetch(:code) }).to eq(["ABC"])
    abc = groups.first
    expect(abc.fetch(:label)).to eq("Projekt ABC")
    expect(abc.fetch(:amount)).to eq(15_000.0)
    expect(result.fetch(:income_statement).fetch(:revenue)).to eq(15_000.0)
  end

  it "lists accounts for one month grouped by cost center" do
    typed = SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type3_sample.se"))
    result = described_class.new(typed).account_movements(month: "2024-01", dimension: :cost_center)

    row = result.find { |account| account.fetch(:account_number) == 3010 && account[:dimension_code] == "ABC" }
    expect(row).to include(movement: 50_000.0, dimension_label: "Avdelning ABC")
    project_only = result.none? { |account| account[:dimension_label] == "Projekt ABC" }
    expect(project_only).to be(true)
  end

  it "computes mid-year account checks from cumulative period balances" do
    checks = analysis.account_summary(3010, month: "2024-03")

    expect(checks.fetch(:opening_balance)).to eq(220_000.0)
    expect(checks.fetch(:movement)).to eq(80_000.0)
    expect(checks.fetch(:closing_balance)).to eq(300_000.0)
  end

  it "computes day checks from voucher movements after month opening" do
    typed = SieAnalysis::Parser.parse(File.read("spec/fixtures/sie_type4_sample.se"))
    checks = described_class.new(typed).account_summary(3010, on: Date.new(2024, 3, 15))

    expect(checks.fetch(:period)).to eq(from: Date.new(2024, 3, 15), to: Date.new(2024, 3, 15))
    expect(checks.fetch(:opening_balance)).to eq(220_000.0)
    expect(checks.fetch(:movement)).to eq(500.0)
    expect(checks.fetch(:closing_balance)).to eq(220_500.0)
  end

  it "raises ArgumentError for invalid analysis arguments" do
    expect { analysis.account_summary(3010) }
      .to raise_error(ArgumentError, "month or on is required")
    expect { analysis.account_movements(month: "invalid") }
      .to raise_error(ArgumentError, "month must be YYYY-MM")
    expect { analysis.account_movements(month: "2024-01", dimension: :unknown) }
      .to raise_error(ArgumentError, "Unsupported dimension")
  end

end
