# -*- coding:binary; frozen_string_literal: true -*-

each_sample("**/*.jpg") do |src_fname|
  src_bname = File.basename(src_fname)

  next if src_fname["/fuzz"]
  next if src_fname["/crash"]
  next if src_fname["lossless"]
  next if src_bname == "testorig12.jpg"     # convert: Unsupported JPEG data precision 12
  next if src_bname == "red-bad-marker.jpg" # convert: Unsupported marker type 0xb6

  dst_fname = src_fname.sub(/\.(\w+)$/, ".im.png")
  system("convert", src_fname, dst_fname, exception: true) unless File.exist?(dst_fname)

  dst_format = "png"
  dst_bname = File.basename(dst_fname)
  RSpec.describe src_fname do
    it "matches #{dst_fname}" do
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
        tmp_fname = "#{src_fname.sub(/.jpg$/, "")}.tmp.png"
        File.binwrite(tmp_fname, src_img.to_png.export)
        raise "zimg --compare #{dst_fname} #{tmp_fname}"
      end
    end
  end
end
