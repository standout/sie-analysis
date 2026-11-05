# frozen_string_literal: true

RSpec.describe "Analysis input safety" do
  def parse(rows = "", type: 2)
    SieAnalysis::Parser.parse("#SIETYP #{type}\n#RAR 0 20240101 20241231\n#{rows}")
  end

  it "rejects missing, unsupported, duplicate or invalid headers" do
    ["", "garbage", "#SIETYP 2", "#RAR 0 20240101 20241231",
     "#SIETYP 1\n#RAR 0 20240101 20241231",
     "#SIETYP 2\n#SIETYP 4\n#RAR 0 20240101 20241231",
     "#SIETYP 2\n#RAR 0 20241231 20240101"].each do |text|
      expect { SieAnalysis::Parser.parse(text) }.to raise_error(SieAnalysis::ParseError)
    end
  end

  it "rejects malformed financial rows instead of reporting partial totals" do
    ["#IB 0 1930 broken", "#UB 0 1930 1e999", "#RES 0 BAD 100",
     "#PSALDO 0 202401 3010 {} secret", "#PSALDO 0 202401 3010 {} 1e999",
     "#PSALDO BAD 202401 3010 {} 100", "#PSALDO 0 202413 3010 {} 100",
     '#PSALDO 0 202401 3010 {1} 100'].each do |row|
      expect { parse("#PSALDO 0 202401 3010 {} -100\n#{row}") }
        .to raise_error(SieAnalysis::ParseError, "Unreadable financial export")
    end
  end

  it "rejects malformed voucher dates, amounts and orphan transactions" do
    ['#VER "A" 1 20240230 "Sale"', '#TRANS 3010 {} 100',
     "#VER A 1 20240101 Sale\n#TRANS 3010 {} secret",
     "#VER A 1 20240101 Sale\n#TRANS 3010 {} 1e999"].each do |rows|
      expect { parse(rows, type: 4) }.to raise_error(SieAnalysis::ParseError)
    end
  end

  it "distinguishes an empty SIE 4 ledger from missing transaction data" do
    [2, 3].each do |type|
      analysis = SieAnalysis::Analysis.new(parse(type: type))
      expect { analysis.account_summary(3010, on: Date.new(2024, 1, 1)) }
        .to raise_error(ArgumentError, /SIE 4/)
      expect { analysis.vouchers_on_account(3010,
        from: Date.new(2024, 1, 1), to: Date.new(2024, 1, 31)) }
        .to raise_error(ArgumentError, /SIE 4/)
    end
    analysis = SieAnalysis::Analysis.new(parse(type: 4))
    expect(analysis.account_summary(3010, on: Date.new(2024, 1, 1))[:movement]).to eq(0)
  end

  it "rejects reversed dates both within and across months" do
    analysis = SieAnalysis::Analysis.new(parse(type: 4))
    [Date.new(2024, 1, 31), Date.new(2024, 2, 1)].each do |first|
      last = Date.new(2024, 1, 1)
      expect { analysis.overview(from: first, to: last) }.to raise_error(ArgumentError, /Start date/)
      expect { analysis.vouchers_on_account(3010, from: first, to: last) }
        .to raise_error(ArgumentError, /Start date/)
    end
  end

  it "does not add missing months when reading reports" do
    parsed = parse
    parsed.period_changes.freeze
    parsed.budgets.freeze
    analysis = SieAnalysis::Analysis.new(parsed)
    analysis.account_movements(month: "2024-01")
    analysis.account_summary(1930, month: "2024-02")
    analysis.overview(from: Date.new(2024, 1, 1), to: Date.new(2024, 3, 31))
    expect(parsed.period_changes).to be_empty
    expect(parsed.budgets).to be_empty
  end

  it "keeps dimension allocations out of undimensioned account balances" do
    analysis = SieAnalysis::Analysis.new(parse(<<~SIE))
      #IB 0 1930 100
      #PSALDO 0 202401 1930 {} 50
      #PSALDO 0 202401 1930 {1 "ABC"} 50
    SIE
    expect(analysis.account_summary(1930, month: "2024-01"))
      .to include(opening_balance: 100.0, movement: 50.0, closing_balance: 150.0)
  end

  it "packages the header and logo attribution with the README" do
    files = Gem::Specification.load("sie-analysis.gemspec").files
    expect(files).to include("assets/header-vector.svg")
    expect(File.read("assets/header-vector.svg")).to include("Copyright © 2006 Yukihiro Matsumoto",
      "https://creativecommons.org/licenses/by-sa/2.5/")
  end
end
