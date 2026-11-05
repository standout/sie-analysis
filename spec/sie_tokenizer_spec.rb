# frozen_string_literal: true

RSpec.describe SieAnalysis::SieTokenizer do
  it "keeps escaped quotes inside quoted fields" do
    tokens = described_class.tokenize('KONTO 3010 "Hej \"varlden\""')

    expect(tokens).to eq(["KONTO", "3010", 'Hej "varlden"'])
  end

  it "keeps object lists as a single token" do
    tokens = described_class.tokenize('PSALDO 0 202401 3010 {1 "ABC"} -50000.00')

    expect(tokens[4]).to eq('{1 "ABC"}')
    expect(tokens[5]).to eq("-50000.00")
  end

  it "preserves empty quoted fields" do
    tokens = described_class.tokenize('VER "" 5 20240315 "March sale"')

    expect(tokens).to eq(["VER", "", "5", "20240315", "March sale"])
  end
end
