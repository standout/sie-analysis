# frozen_string_literal: true

RSpec.describe "SIE dimensions" do
  def parse_rows(rows)
    SieAnalysis::Parser.parse("#SIETYP 4\n#RAR 0 20240101 20241231\n#{rows}")
  end

  { cost_center: 1, cost_bearer: 2, project: 6, employee: 7,
    customer: 8, supplier: 9, invoice: 10, 20 => 20 }.each do |name, number|
    it "reports #{name} without mixing objects from another dimension" do
      document = parse_rows(<<~SIE)
        #KONTO 3010 "Sales"
        #OBJEKT #{number} "A" "Selected"
        #PSALDO 0 202401 3010 {#{number} "A"} -100
        #PSALDO 0 202401 3010 {21 "A"} -900
        #PBUDGET 0 202401 3010 {#{number} "A"} -80
      SIE
      analysis = SieAnalysis::Analysis.new(document)
      expect(analysis.available_dimensions).to include(name, 21)
      report = analysis.overview(from: Date.new(2024, 1, 1), to: Date.new(2024, 1, 31), dimension: name)
      expect(report.dig(:income_statement, :revenue)).to eq(BigDecimal("100"))
      expect(report.dig(:budget, :rows).first).to include(actual: BigDecimal("100"), budget: BigDecimal("80"))
      expect(analysis.account_movements(month: "2024-01", dimension: number)).to contain_exactly(
        include(dimension_code: "A", dimension_label: "Selected", movement: BigDecimal("100"))
      )
    end
  end

  it "preserves declared names and discovers dimensions from every supported source" do
    document = parse_rows(<<~SIE)
      #DIM 20 "Department"
      #UNDERDIM 21 "Team" 20
      #OBJEKT 22 "A" "Office"
      #PSALDO 0 202401 3010 {23 "A"} -100
      #PBUDGET 0 202401 3010 {24 "A"} -80
      #VER A 1 20240101 "Sale"
      {
      #TRANS 3010 {25 "A"} -100
      }
    SIE
    expect(document.dimensions).to eq(20 => "Department", 21 => "Team")
    expect(document.vouchers.first.lines.first.objects).to eq([[25, "A"]])
    analysis = SieAnalysis::Analysis.new(document)
    expect(analysis.available_dimensions).to eq([20, 21, 22, 23, 24, 25])
    expect(analysis.account_movements(month: "2024-01", dimension: 25)).to eq([])
    expect { analysis.account_movements(month: "2024-01", dimension: 26) }.to raise_error(ArgumentError)
    [0, -1, "20", :unknown].each do |dimension|
      expect { analysis.account_movements(month: "2024-01", dimension:) }.to raise_error(ArgumentError)
    end
  end
end
