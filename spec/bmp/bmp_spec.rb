# frozen_string_literal: true

each_sample("bmp/mouse*.bmp") do |fname|
  RSpec.describe fname do
    subject(:bmp) { ZIMG.load(fname) }
    let!(:png) { ZIMG.load(fname.gsub("bmp", "png")) }

    its(:width)  { is_expected.to eq(png.width) }
    its(:height) { is_expected.to eq(png.height) }
    its(:format) { is_expected.to eq(:bmp) }
    it           { is_expected.to eq(png) }

    it "restores original imagedata" do
      expect(File.binread(fname)).to include(bmp.imagedata)
    end
  end
end
