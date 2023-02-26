# frozen_string_literal: true

PNGSuite.each_good do |fname|
  RSpec.describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
    it "accessess all pixels via enumerator" do
      img = ZIMG.load(fname)

      first_pixel = img.pixels.first

      n = 0
      img.pixels.each do |px|
        expect(px).to be_instance_of(ZIMG::Color)
        expect(px).to eq first_pixel if n == 0
        n += 1
      end
      expect(n).to eq img.width * img.height
    end
  end
end

RSpec.describe "pixels enumerator" do
  describe "#uniq" do
    it "returns only unique pixels" do
      fname = File.join(PNG_SAMPLES_DIR, "qr_bw.png")
      img = ZIMG.load(fname)
      a = img.pixels.uniq
      expect(a.size).to eq 2
      expect(a.sort).to eq [ZIMG::Color::BLACK, ZIMG::Color::WHITE].sort
    end
  end
end
