# -*- coding:binary; frozen_string_literal: true -*-

require "iostruct"

module ZIMG
  module BMP
    class BITMAPFILEHEADER < IOStruct.new "VvvV", # a2VvvV',
      # :bfType,
      :bfSize,      # the size of the BMP file in bytes
      :bfReserved1,
      :bfReserved2,
      :bfOffBits    # imagedata offset

      def inspect
        "<#{super.partition(self.class.to_s.split("::").last)[1..].join}"
      end
    end

    class BITMAPINFOHEADER < IOStruct.new "V3v2V6",
      :biSize, # BITMAPINFOHEADER::SIZE
      :biWidth,
      :biHeight,
      :biPlanes,
      :biBitCount,
      :biCompression,
      :biSizeImage,
      :biXPelsPerMeter,
      :biYPelsPerMeter,
      :biClrUsed,
      :biClrImportant

      def inspect
        "<#{super.partition(self.class.to_s.split("::").last)[1..].join}"
      end
    end

    class BmpHdrPseudoChunk < Chunk # ::IHDR
      # bmp_hdr is a BITMAPINFOHEADER
      def initialize(bmp_hdr)
        @bmp_hdr = bmp_hdr
        h = {
          width:  bmp_hdr.biWidth,
          height: bmp_hdr.biHeight.abs,
          type:   "BITMAPINFOHEADER",
          crc:    :no_crc # for CLI
        }
        if bmp_hdr.biBitCount == 8
          h[:color] = COLOR_INDEXED
          h[:depth] = 8
        else
          h[:bpp] = bmp_hdr.biBitCount
        end
        super(h)
        self.data = bmp_hdr.pack
      end

      def inspect *_args
        @bmp_hdr.inspect
      end

      def method_missing mname, *args
        if @bmp_hdr.respond_to?(mname)
          @bmp_hdr.send(mname, *args)
        else
          super
        end
      end

      def respond_to_missing?(mname, include_private = false)
        @bmp_hdr.respond_to?(mname) || super
      end
    end

    class BmpPseudoChunk < Chunk
      def initialize(struct)
        @struct = struct
        type =
          if struct.respond_to?(:type)
            struct.type
          else
            struct.class.to_s.split("::").last
          end

        super(
          # :size    => struct.class.const_get('SIZE'),
          type: type,
          data: struct.pack,
          crc:  :no_crc # for CLI
        )
      end

      def inspect *_args
        @struct.inspect
      end

      def method_missing mname, *args
        if @struct.respond_to?(mname)
          @struct.send(mname, *args)
        else
          super
        end
      end

      def respond_to_missing?(mname, include_private = false)
        @struct.respond_to?(mname) || super
      end
    end

    class BmpPaletteChunk < Chunk # ::PLTE
      def initialize(data)
        super(
          crc:  :no_crc,
          data: data,
          type: "PALETTE"
        )
      end

      def [](idx)
        rgbx = @data[idx * 4, 4]
        rgbx && Color.new(*rgbx.unpack("C4"))
      end

      def []=(idx, color)
        @data ||= ""
        @data[idx * 4, 4] = [color.r, color.g, color.b, color.a].pack("C4")
      end

      def ncolors
        @data.to_s.size / 4
      end

      def inspect *_args
        format("<%s ncolors=%d>", "PALETTE", size / 4)
      end
    end

    class Color < ZIMG::Color
      # BMP pixels are in perverted^w reverted order - BGR instead of RGB
      def initialize *a
        h = a.last.is_a?(Hash) ? a.pop : {}
        case a.size
        when 3
          # BGR
          super(*a.reverse, h)
        when 4
          # ABGR
          super a[2], a[1], a[0], a[3], h
        else
          super
        end
      end
    end
  end # BMP
end # ZIMG
