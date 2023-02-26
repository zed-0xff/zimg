# frozen_string_literal: true

CROP_WIDTH  = 10
CROP_HEIGHT = 10
CROP_SAMPLE = File.join(PNG_SAMPLES_DIR, "captcha_4bpp.png")

QR_SQUARE = <<~EOQR
  #######
  #.....#
  #.###.#
  #.###.#
  #.###.#
  #.....#
  #######
EOQR

RSpec.describe ZIMG::Image do
  describe "crop" do
    it "crops and keeps original image unchanged" do
      src1 = ZIMG.load(CROP_SAMPLE)
      src2 = ZIMG.load(CROP_SAMPLE)
      dest = src1.crop width: CROP_WIDTH, height: CROP_HEIGHT

      expect(dest.width).to  eq CROP_WIDTH
      expect(dest.height).to eq CROP_HEIGHT

      expect(dest.width).not_to  eq src1.width
      expect(dest.height).not_to eq src1.height

      expect(src1.export).to eq src2.export
      expect(src1.export).not_to eq dest.export
      expect(src2.export).not_to eq dest.export
    end
  end

  describe "crop! result" do
    let!(:img) do
      ZIMG.load(CROP_SAMPLE).crop! width: CROP_WIDTH, height: CROP_HEIGHT
    end

    it "has #{CROP_HEIGHT} scanlines" do
      expect(img.scanlines.size).to eq CROP_HEIGHT
    end

    CROP_HEIGHT.times do |i|
      it "calculates proper #size" do
        scanline_size = (img.hdr.bpp * img.width / 8).ceil + 1
        expect(img.scanlines[i].size).to eq scanline_size
      end

      it "exports proper count of bytes" do
        scanline_size = (img.hdr.bpp * img.width / 8).ceil + 1
        expect(img.scanlines[i].export.size).to eq scanline_size
      end
    end

    describe "reimported" do
      let!(:img2) { described_class.new(img.export) }

      it "has #{CROP_HEIGHT} scanlines" do
        expect(img2.scanlines.size).to eq CROP_HEIGHT
      end
    end
  end

  each_sample("png/qr_*.png") do |fname|
    describe fname do
      let!(:img) { ZIMG.load fname }

      it "extracts left square" do
        img.crop! x: 1, y: 1, width: 7, height: 7
        expect(img.to_ascii("#.").strip).to eq QR_SQUARE.strip
      end

      it "extracts right square" do
        img.crop! x: 27, y: 1, width: 7, height: 7
        expect(img.to_ascii("#.").strip).to eq QR_SQUARE.strip
      end

      it "extracts bottom square" do
        img.crop! x: 1, y: 27, width: 7, height: 7
        expect(img.to_ascii("#.").strip).to eq QR_SQUARE.strip
      end

      it "keeps whole original image if crop is larger than image" do
        img2 = img.crop x: 0, y: 0, width: 7000, height: 7000
        expect(img2.width).to eq img.width
        expect(img2.height).to eq img.height
        expect(img2.to_ascii).to eq img.to_ascii
      end
    end
  end
end
