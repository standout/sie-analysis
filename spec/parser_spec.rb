# frozen_string_literal: true

RSpec.describe SieAnalysis::Parser do
  it "parses accounts, balances, and period changes from a type 2 export" do
    text = File.read("spec/fixtures/sie_type2_sample.se")
    parsed = described_class.parse(text)

    expect(parsed.accounts[3010]).to eq("Forsaljning")
    expect(parsed.opening_balances[1930]).to eq(100_000.0)
    expect(parsed.results[3010]).to eq(-500_000.0)
    expect(parsed.period_changes["202401"][3010]).to eq(-100_000.0)
    expect(parsed.financial_years[0]).to include(from: "20240101", to: "20241231")
  end

  it "parses dimension objects keyed by dimension number and code" do
    text = File.read("spec/fixtures/sie_type3_sample.se")
    parsed = described_class.parse(text)

    expect(parsed.objects[[1, "ABC"]]).to eq("Avdelning ABC")
    expect(parsed.objects[[6, "ABC"]]).to eq("Projekt ABC")
    expect(parsed.period_changes["202401"][[3010, 1, "ABC"]]).to eq(-50_000.0)
    expect(parsed.period_changes["202401"][[3010, 1, "XYZ"]]).to eq(-35_000.0)
    expect(parsed.period_changes["202401"][[3010, 6, "ABC"]]).to eq(-15_000.0)
    expect(parsed.vouchers).to eq([])
  end

  it "parses voucher transactions from a type 4 export" do
    text = File.read("spec/fixtures/sie_type4_sample.se")
    parsed = described_class.parse(text)
    sale = parsed.vouchers.find { |voucher| voucher.number == 1 }
    blank_series = parsed.vouchers.find { |voucher| voucher.number == 5 }

    expect(sale.series).to eq("A")
    expect(sale.date).to eq(Date.new(2024, 1, 10))
    expect(sale.description).to eq("Sale")
    expect(sale.lines).to contain_exactly(
      have_attributes(account: 3010, amount: -1000.0),
      have_attributes(account: 1930, amount: 1000.0)
    )
    expect(blank_series.series).to eq("")
    expect(blank_series.date).to eq(Date.new(2024, 3, 15))
  end
end
