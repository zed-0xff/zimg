# -*- coding:binary; frozen_string_literal: true -*-

each_sample("**/*.jpg").sort_by(&:size).each do |src_fname|
  next unless src_fname["lossless"]

  src_bname = File.basename(src_fname)
  dst_fname = src_fname.sub(/jpg$/, "png")
  bname = File.basename(src_fname)

  RSpec.describe src_fname do
    it "matches #{dst_fname}" do
      skip("SLOW") if bname == "jpeg_lossless_sel1-rgb.jpg" && !ENV["SLOW"]
      jpg = ZIMG.load(src_fname)
      jpg.to_rgb
      skip "TBD"
    end
  end
end
