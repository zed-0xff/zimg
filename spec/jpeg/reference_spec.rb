# -*- coding:binary; frozen_string_literal: true -*-

require "digest/md5"

processed = {}
each_sample("**/*.jpg").sort_by(&:size).each do |src_fname|
  src_bname = File.basename(src_fname)

  next if src_fname["/fuzz"]
  next if src_fname["/crash"]
  next if src_fname["lossless"]             # convert: Unsupported JPEG process: SOF type 0xc3
  next if src_bname == "testorig12.jpg"     # TODO: convert: Unsupported JPEG data precision 12
  next if src_bname == "red-bad-marker.jpg" # TODO: convert: Unsupported marker type 0xb6

  md5 = Digest::MD5.file(src_fname).to_s
  next if processed[md5]

  processed[md5] = true

  dst_fname = src_fname.sub(/\.(\w+)$/, ".im.png")
  unless File.exist?(dst_fname)
    system("convert", "-define", "jpeg:block-smoothing=false", src_fname, dst_fname,
      exception: true)
  end

  dst_format = "png"
  RSpec.describe src_fname do
    it "matches #{dst_fname}" do
      skip("SLOW") if src_bname == "jpeg_lossless_sel1-rgb.jpg" && !ENV["SLOW"]
      skip("SLOW") if src_bname == "large_image.jpg" && !ENV["SLOW"]
      skip("SLOW") if src_bname == "black-6000x6000.jpg" && !ENV["SLOW"]

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
        File.binwrite(tmp_fname, src_img.to_png.export) # FIXME: calls pixel processing 2nd time!
        raise "zimg --compare #{dst_fname} #{tmp_fname}"
      end
    end
  end
end
