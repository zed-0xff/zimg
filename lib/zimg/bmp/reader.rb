# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module BMP
    TypedBlock = Struct.new(:type, :size, :offset, :data) do # rubocop:disable Lint/StructNewOverride
      def inspect
        # string length of 16 is for alignment with BITMAP....HEADER chunks on
        # zpng CLI output
        format("<%s size=%-5d (0x%-4x) offset=%-5d (0x%-4x)>", type, size, size, offset, offset)
      end

      def pack
        data
      end
    end

    module ImageMixin
      def imagedata
        @imagedata ||= @scanlines.sort_by(&:offset).map(&:decoded_bytes).join
      end
    end

    module Reader
      # http://en.wikipedia.org/wiki/BMP_file_format

      def _read_bmp(io)
        fhdr = BITMAPFILEHEADER.read(io)
        # DIB Header immediately follows the Bitmap File Header
        ihdr = BITMAPINFOHEADER.read(io)
        if ihdr.biSize != BITMAPINFOHEADER::SIZE
          raise "dib_hdr_size #{ihdr.biSize} unsupported, want #{BITMAPINFOHEADER::SIZE}"
        end

        @new_image = true
        @color_class = BMP::Color
        @format = :bmp
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
          @scanlines.unshift ScanLine.new(self, height - idx - 1,
            decoded_bytes: data,
            size:          row_size,
            offset:        offset)
        end

        @chunks << BmpPseudoChunk.new(
          TypedBlock.new("IMAGEDATA", io.tell - pos0, pos0, "")
        )

        unless io.eof?
          @chunks << BmpPseudoChunk.new(
            TypedBlock.new("GAP2", io.size - io.tell, io.tell, "")
          )
        end

        extend ImageMixin
      end
    end # Reader
  end # BMP
end # ZIMG
