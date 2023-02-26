# frozen_string_literal: true

PNGSuite.each("???i*.png") do |fname|
  RSpec.describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
    it "deinterlaced should be pixel-by-pixel-identical to interlaced" do
      interlaced = ZIMG.load(fname)
      deinterlaced = interlaced.deinterlace
      deinterlaced.each_pixel do |color, x, y|
        expect(interlaced[x, y]).to eq color
      end
      interlaced.each_pixel do |color, x, y|
        expect(deinterlaced[x, y]).to eq color
      end

      expect(interlaced.pixels.to_a).to eq deinterlaced.pixels.to_a
    end
  end
end
