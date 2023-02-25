# frozen_string_literal: true

require "set"

PNGSuite.each_good do |fname|
  RSpec.describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
    it "accessess all pixels" do
      img = ZIMG.load(fname)
      n = 0
      img.each_pixel do |px|
        expect(px).to be_instance_of(ZIMG::Color)
        n += 1
      end
      expect(n).to eq img.width * img.height
    end

    it "accessess all pixels with coords" do
      img = ZIMG.load(fname)
      n = 0
      ax = Set.new
      ay = Set.new
      img.each_pixel do |px, x, y|
        expect(px).to be_instance_of(ZIMG::Color)
        n += 1
        ax << x
        ay << y
      end
      expect(n).to eq img.width * img.height
      expect(ax.size).to eq img.width
      expect(ay.size).to eq img.height
    end

    it "accessess all pixels using method #2" do
      img = ZIMG.load(fname)
      n = 0
      a = img.each_pixel.to_a
      ax = Set.new
      ay = Set.new
      a.each do |px, x, y|
        expect(px).to be_instance_of(ZIMG::Color)
        n += 1
        ax << x
        ay << y
      end
      expect(n).to eq img.width * img.height
      expect(ax.size).to eq img.width
      expect(ay.size).to eq img.height
    end
  end
end
