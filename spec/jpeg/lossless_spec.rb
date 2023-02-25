# -*- coding:binary; frozen_string_literal: true -*-

each_sample("jpeg/jpeg-decoder/tests/reftest/images/lossless/*.jpg") do |fname|
  dst_fname = fname.sub(/jpg$/, "png")
  bname = File.basename(fname)

  RSpec.describe fname do
    it "matches #{dst_fname}" do
      skip("SLOW") if bname == "jpeg_lossless_sel1-rgb.jpg" && !ENV["SLOW"]
      jpg = ZIMG.load(fname)
      jpg.to_rgb
    end
  end
end
