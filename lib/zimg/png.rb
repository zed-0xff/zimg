# -*- coding:binary; frozen_string_literal: true -*-

require "English"
module ZIMG
  module PNG
    MAGIC = "\x89PNG\x0d\x0a\x1a\x0a"

    COLOR_GRAYSCALE  = 0  # Each pixel is a grayscale sample
    COLOR_RGB        = 2  # Each pixel is an R,G,B triple.
    COLOR_INDEXED    = 3  # Each pixel is a palette index; a PLTE chunk must appear.
    COLOR_GRAY_ALPHA = 4  # Each pixel is a grayscale sample, followed by an alpha sample.
    COLOR_RGBA       = 6  # Each pixel is an R,G,B triple, followed by an alpha sample.

    def read_png(io)
      prev_chunk = nil
      until io.eof?
        chunk = Chunk.from_stream(io)
        # heuristics
        if prev_chunk&.check(type: true, crc: false) &&
           chunk.check(type: false, crc: false) && chunk.data && _apply_heuristics(io, prev_chunk, chunk)
          redo
        end
        chunk.idx = @chunks.size
        @chunks << chunk
        prev_chunk = chunk
        break if chunk.is_a?(Chunk::IEND)
      end
    end

    ###########################################################################
    # chunks access

    def ihdr
      @ihdr ||= @chunks.find { |c| c.is_a?(Chunk::IHDR) }
    end
    alias header ihdr
    alias hdr ihdr

    def trns
      # not used "@trns ||= ..." here b/c it will call find() each time of there's no TRNS chunk
      defined?(@trns) ? @trns : (@trns = @chunks.find { |c| c.is_a?(Chunk::TRNS) })
    end

    def plte
      @plte ||= @chunks.find { |c| c.is_a?(Chunk::PLTE) }
    end
    alias palette plte

    ###########################################################################
    # image attributes

    def bpp
      ihdr && @ihdr.bpp
    end

    def width
      ihdr && @ihdr.width
    end

    def height
      ihdr && @ihdr.height
    end

    def interlaced?
      ihdr && @ihdr.interlace != 0
    end

    def adam7
      @adam7 ||= Adam7Decoder.new(width, height, bpp)
    end

    def [](x, y)
      # extracting this check into a module => +1-2% speed
      x, y = adam7.convert_coords(x, y) if interlaced?
      scanlines[y][x]
    end

    def imagedata
      @imagedata ||=
        begin
          warn "[?] no image header, assuming non-interlaced RGB".yellow unless ihdr
          data = _imagedata
          data && !data.empty? ? _safe_inflate(data) : ""
        end
    end

    def scanlines
      @scanlines ||=
        begin
          r = []
          n = interlaced? ? adam7.scanlines_count : height.to_i
          n.times do |i|
            r << Scanline.new(self, i)
          end
          r.delete_if(&:bad?)
          r
        end
    end

    def _alpha_color(color)
      return nil unless trns

      # For color type 0 (grayscale), the tRNS chunk contains a single gray level value, stored in the format:
      #
      #   Gray:  2 bytes, range 0 .. (2^bitdepth)-1
      #
      # For color type 2 (truecolor), the tRNS chunk contains a single RGB color value, stored in the format:
      #
      #   Red:   2 bytes, range 0 .. (2^bitdepth)-1
      #   Green: 2 bytes, range 0 .. (2^bitdepth)-1
      #   Blue:  2 bytes, range 0 .. (2^bitdepth)-1
      #
      # (If the image bit depth is less than 16, the least significant bits are used and the others are 0)
      # Pixels of the specified gray level are to be treated as transparent (equivalent to alpha value 0);
      # all other pixels are to be treated as fully opaque ( alpha = (2^bitdepth)-1 )

      @alpha_color ||=
        case hdr.color
        when COLOR_GRAYSCALE
          v = trns.data.unpack1("n") & (2**hdr.depth - 1)
          Color.from_grayscale(v, depth: hdr.depth)
        when COLOR_RGB
          a = trns.data.unpack("n3").map { |v| v & (2**hdr.depth - 1) } # rubocop:disable Lint/ShadowingOuterLocalVariable
          Color.new(*a, depth: hdr.depth)
        else
          raise StandardError, "color2alpha only intended for GRAYSCALE & RGB color modes"
        end

      color == @alpha_color ? 0 : (2**hdr.depth - 1)
    end

    private

    def _imagedata
      data_chunks = @chunks.find_all { |c| c.is_a?(Chunk::IDAT) }
      case data_chunks.size
      when 0
        # no imagedata chunks ?!
        nil
      when 1
        # a single chunk - save memory and return a reference to its data
        data_chunks[0].data
      else
        # multiple data chunks - join their contents
        data_chunks.map(&:data).join
      end
    end

    # unpack zlib,
    # on errors keep going and try to return maximum possible data
    def _safe_inflate(data)
      zi = Zlib::Inflate.new
      pos = 0
      r = String.new
      begin
        # save some memory by not using String#[] when not necessary
        r << zi.inflate(pos == 0 ? data : data[pos..])
        if zi.total_in < data.size
          @extradata << data[zi.total_in..]
          warn "[?] #{@extradata.last.size} bytes of extra data after zlib stream".red if @verbose >= 1
        end
        # decompress OK
      rescue Zlib::BufError, Zlib::DataError, Zlib::NeedDict
        # tried to decompress, but got EOF - need more data
        warn "[!] #{$ERROR_INFO.inspect}".red if @verbose >= -1
        # collect any remaining data in decompress buffer
        r << zi.flush_next_out
      end

      r == "" ? nil : r
    ensure
      zi.close if zi && !zi.closed?
    end
  end
end

require_relative "png/adam7_decoder"
require_relative "png/chunks"
require_relative "png/scanline"
require_relative "png/scanline_mixins"

ZIMG.register_format! :png
