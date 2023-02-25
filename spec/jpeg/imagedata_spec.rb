# -*- coding:binary; frozen_string_literal: true -*-

each_sample("jpeg/**/*.{cmyk,rgb,rgba}") do |dst_fname|
  src_fname = dst_fname.sub(/(cmyk|rgba?)$/, "jpg")
  next unless File.exist?(src_fname)

  dst_format = Regexp.last_match(1)
  dst_bname = File.basename(dst_fname)
  RSpec.describe src_fname do
    it "matches #{dst_bname}" do
      dst = File.binread(dst_fname)
      src = ZIMG.load(src_fname)
      src =
        case dst_format
        when "rgb"
          src.to_rgb
        when "rgba", "cmyk"
          src.to_rgba
        end
      expect(src.size).to eq(dst.size)
      if src != dst
        tmp_fname = "#{src_fname.sub(/.jpg$/, "")}.tmp"
        File.binwrite(tmp_fname, src)
        raise "#{tmp_fname} is not equal to #{dst_fname}"
      end
    end
  end
end
