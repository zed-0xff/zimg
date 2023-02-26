# frozen_string_literal: true

PNGSuite.each("tb", "tp1") do |fname|
  RSpec.describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
    it "has its very first pixel transparent" do
      img = ZIMG.load(fname)
      expect(img[0, 0]).to be_transparent
    end

    it "has its very first pixel NOT opaque" do
      img = ZIMG.load(fname)
      expect(img[0, 0]).not_to be_opaque
    end
  end
end

PNGSuite.each("tp0") do |fname|
  RSpec.describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
    it "has its very first pixel NOT transparent" do
      img = ZIMG.load(fname)
      expect(img[0, 0]).not_to be_transparent
    end

    it "has its very first pixel opaque" do
      img = ZIMG.load(fname)
      expect(img[0, 0]).to be_opaque
    end
  end
end
