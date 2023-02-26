# frozen_string_literal: true

RSpec.describe ZIMG::Color do
  ZIMG::Color::ANSI_COLORS.each do |color_sym|
    it "finds closest color for #{color_sym}" do
      color = described_class.const_get(color_sym.to_s.upcase)
      expect(color.to_ansi).to eq color_sym
    end
  end

  describe "to_depth" do
    it "decreases color depth" do
      c = described_class.new 0x10, 0x20, 0x30
      c = c.to_depth(4)
      expect(c.depth).to eq 4
      expect(c.r).to eq 1
      expect(c.g).to eq 2
      expect(c.b).to eq 3
    end

    it "increases color depth" do
      c = described_class.new 0, 2, 3, depth: 4
      c = c.to_depth(8)
      expect(c.depth).to eq 8
      expect(c.r).to eq 0
      expect(c.g).to eq 2 * 17
      expect(c.b).to eq 3 * 17
    end

    it "keeps color depth" do
      c = described_class.new 0x11, 0x22, 0x33
      c = c.to_depth(8)
      expect(c.depth).to eq 8
      expect(c.r).to eq 0x11
      expect(c.g).to eq 0x22
      expect(c.b).to eq 0x33
    end
  end

  it "sorts" do
    c1 = described_class.new 0x11, 0x11, 0x11
    c2 = described_class.new 0x22, 0x22, 0x22
    c3 = described_class.new 0, 0, 0xff

    expect([c3, c1, c2].sort).to eq [c1, c2, c3]
    expect([c3, c2, c1].sort).to eq [c1, c2, c3]
    expect([c1, c3, c2].sort).to eq [c1, c2, c3]
  end

  describe "#from_html" do
    it "understands short notation" do
      expect(described_class.from_html("#ff1133")).to eq described_class.new(0xff, 0x11, 0x33)
    end

    it "understands long notation" do
      expect(described_class.from_html("#f13")).to eq described_class.new(0xff, 0x11, 0x33)
    end

    it "understands short notation w/o '#'" do
      expect(described_class.from_html("ff1133")).to eq described_class.new(0xff, 0x11, 0x33)
    end

    it "understands long notation w/o '#'" do
      expect(described_class.from_html("f13")).to eq described_class.new(0xff, 0x11, 0x33)
    end

    it "sets alpha" do
      expect(described_class.from_html("f13", alpha: 0x11)).to eq described_class.new(0xff, 0x11, 0x33, 0x11)

      expect(described_class.from_html("#f13", a: 0x44)).to eq described_class.new(0xff, 0x11, 0x33, 0x44)

      expect(described_class.from_html("f13")).not_to eq described_class.new(0xff, 0x11, 0x33, 0x11)
    end
  end
end
