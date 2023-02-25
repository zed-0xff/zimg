# -*- coding:binary; frozen_string_literal: true -*-

# http://en.wikipedia.org/wiki/BMP_file_format

module ZIMG
  module BMP
    MAGIC = "BM"

    def imagedata
      @imagedata ||= @scanlines.sort_by(&:offset).map(&:decoded_bytes).join
    end

    def ihdr
      @ihdr ||= @chunks.find { |c| c.is_a?(BmpHdrPseudoChunk) }
    end
    alias hdr ihdr

    def width
      ihdr && @ihdr.width
    end

    def height
      ihdr && @ihdr.height
    end

    def trns
      nil
    end

    def read_bmp(io)
      fhdr = BITMAPFILEHEADER.read(io)
      # DIB Header immediately follows the Bitmap File Header
      ihdr = BITMAPINFOHEADER.read(io)
      if ihdr.biSize != BITMAPINFOHEADER::SIZE
        raise "dib_hdr_size #{ihdr.biSize} unsupported, want #{BITMAPINFOHEADER::SIZE}"
      end

      @new_image = true
      @color_class = BMP::Color
      @chunks << BmpPseudoChunk.new(fhdr)
      @chunks << BmpHdrPseudoChunk.new(ihdr)

      # http://en.wikipedia.org/wiki/BMP_file_format#Pixel_storage
      row_size = ((ihdr.biBitCount * width + 31) / 32) * 4

      gap1_size = fhdr.bfOffBits - io.tell

      warn "[?] negative gap1=#{gap1_size}".red if gap1_size < 0

      if ihdr.biBitCount == 8 && gap1_size >= 1024
        # palette for 256-color BMP
        data = io.read 1024
        @chunks << BmpPaletteChunk.new(data)
        gap1_size -= 1024
      end

      if gap1_size != 0
        @chunks << BmpPseudoChunk.new(
          TypedBlock.new("GAP1", gap1_size, io.tell, io.read(gap1_size))
        )
        # io.seek(fhdr.bfOffBits)
      end

      pos0 = io.tell
      @scanlines = []
      height.times do |idx|
        offset = io.tell - fhdr.bfOffBits
        data = io.read(row_size)
        # BMP scanlines layout is upside-down
        @scanlines.unshift PNG::Scanline.new(self, height - idx - 1,
          decoded_bytes: data,
          size:          row_size,
          offset:        offset)
      end

      @chunks << BmpPseudoChunk.new(
        TypedBlock.new("IMAGEDATA", io.tell - pos0, pos0, "")
      )

      return if io.eof?

      @chunks << BmpPseudoChunk.new(
        TypedBlock.new("GAP2", io.size - io.tell, io.tell, "")
      )
    end
  end
end

require_relative "bmp/color"
require_relative "bmp/chunks"

ZIMG.register_format! :bmp
