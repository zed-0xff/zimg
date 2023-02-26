# -*- coding:binary; frozen_string_literal: true -*-

each_sample("jpeg/**/*.{cmyk,rgb,rgba,png}") do |dst_fname|
  src_fname = dst_fname.sub(/\.(\w+)$/, ".jpg")
  next unless File.exist?(src_fname)

  src_bname = File.basename(src_fname)

  dst_format = Regexp.last_match(1)
  dst_bname = File.basename(dst_fname)
  RSpec.describe src_fname do
    it "matches #{dst_bname}" do
      skip("SLOW") if src_bname == "jpeg_lossless_sel1-rgb.jpg" && !ENV["SLOW"]

      dst = File.binread(dst_fname)
      src_img = ZIMG.load(src_fname)
      src =
        case dst_format
        when "png"
          img = ZIMG::Image.new(dst)
          dst = img.to_rgb
          src_img.to_rgb
        when "rgb"
          src_img.to_rgb
        when "rgba"
          src_img.to_rgba
        else
          raise "unexpected reference format: #{dst_format}"
        end
      expect(src.size).to eq(dst.size)
      if src != dst
        tmp_fname = "#{src_fname.sub(/.jpg$/, "")}.tmp"
        File.binwrite(tmp_fname, src_img.to_png.export)
        raise "#{tmp_fname} is not equal to #{dst_bname}"
      end
    end
  end
end
