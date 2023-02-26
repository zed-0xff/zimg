# frozen_string_literal: true

RSpec.describe ZIMG::Image do
  def _new_img(bpp, color)
    described_class.new(width: 8, height: 8, bpp: bpp, color: color)
  end

  [1, 2, 4, 8].each do |bpp|
    [true, false].each do |color|
      describe "new( bpp: #{bpp}, color: #{color} )" do
        subject { img.hdr }

        let(:img) { _new_img(bpp, color) }

        it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
        it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

        its(:depth) { is_expected.to eq bpp }
        its(:color) { is_expected.to eq(color ? ZIMG::PNG::COLOR_INDEXED : ZIMG::PNG::COLOR_GRAYSCALE) }
      end
    end
  end

  describe "new( bpp: 16, color: false )" do
    subject { img.hdr }

    let(:img) { _new_img(16, false) }

    it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
    it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

    its(:depth) { is_expected.to eq 8 } # 8 bits per color + 8 per alpha = 16 bpp
    its(:color) { is_expected.to eq ZIMG::PNG::COLOR_GRAY_ALPHA }
  end

  describe "new( bpp: 16, color: true )" do
    it "raises error" do
      expect { _new_img(16, true) }.to raise_error(RuntimeError)
    end
  end

  describe "new( bpp: 24, color: false )" do
    subject { img.hdr }

    let(:img) { _new_img(24, false) }

    it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
    it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

    its(:depth) { is_expected.to eq 8 } # each channel depth = 8
    its(:color) { is_expected.to eq ZIMG::PNG::COLOR_RGB }
  end

  describe "new( bpp: 24, color: true )" do
    subject { img.hdr }

    let(:img) { _new_img(24, true) }

    it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
    it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

    its(:depth) { is_expected.to eq 8 } # each channel depth = 8
    its(:color) { is_expected.to eq ZIMG::PNG::COLOR_RGB }
  end

  describe "new( bpp: 32, color: false )" do
    subject { img.hdr }

    let(:img) { _new_img(32, false) }

    it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
    it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

    its(:depth) { is_expected.to eq 8 } # each channel depth = 8
    its(:color) { is_expected.to eq ZIMG::PNG::COLOR_RGBA }
  end

  describe "new( bpp: 32, color: true )" do
    subject { img.hdr }

    let(:img) { _new_img(32, true) }

    it("exports") { expect(img.export).to start_with(ZIMG::PNG::MAGIC) }
    it("to_asciis") { expect(img.to_ascii.split("\n").size).to eq 8 }

    its(:depth) { is_expected.to eq 8 } # each channel depth = 8
    its(:color) { is_expected.to eq ZIMG::PNG::COLOR_RGBA }
  end
end
