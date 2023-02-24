# -*- coding:binary; frozen_string_literal: true -*-

# https://github.com/corkami/formats/blob/master/image/jpeg.md
# https://docs.fileformat.com/image/jpeg/
# https://www.file-recovery.com/jpg-signature-format.htm

module ZIMG
  module JPEG
    SOI = "\xff\xd8" # Start of Image
    EOI = "\xff\xd9" # End of Image

    MAGIC = SOI

    DCT_ZIGZAG = [
      0,
      1, 8,
      16, 9, 2,
      3, 10, 17, 24,
      32, 25, 18, 11, 4,
      5, 12, 19, 26, 33, 40,
      48, 41, 34, 27, 20, 13, 6,
      7, 14, 21, 28, 35, 42, 49, 56,
      57, 50, 43, 36, 29, 22, 15,
      23, 30, 37, 44, 51, 58,
      59, 52, 45, 38, 31,
      39, 46, 53, 60,
      61, 54, 47,
      55, 62,
      63
    ].freeze

    def _read(io)
      @format = :jpeg

      until io.eof?
        marker = io.read(2)
        break if marker == EOI

        case marker[1].ord
        when 0xc4 # overlaps with SOF range!
          @chunks << DHT.new(marker, io)
        when 0xcc # overlaps with SOF range!
          @chunks << DAC.new(marker, io)
        when 0xc0..0xcf
          @chunks << (chunk = SOF.new(marker, io))
          @width = chunk.width
          @height = chunk.height
          @bpp = chunk.bpp
          @sof = chunk
        when 0xda
          @chunks << (sos = SOS.new(marker, io))
          # Entropy-Coded Segment starts
          @chunks << (ecs = ECS.new(io))
          sos.ecs = ecs
        when 0xdb
          @chunks << DQT.new(marker, io)
        when 0xdc
          @chunks << DNL.new(marker, io)
        when 0xdd
          @chunks << (chunk = DRI.new(marker, io))
        when 0xe0..0xef
          @chunks << APP.new(marker, io)
        when 0xfe
          @chunks << COM.new(marker, io)
        when 0xff
          # fill bytes, fixtures/fillbytes.jpg
          io.seek(-2, :CUR) if io.read(1) != 0xff
        else
          warn "[?] Unknown JPEG marker #{marker.inspect}".yellow
          @chunks << Chunk.new(marker, io)
        end
      end
    end

    def clamp8bit(x)
      if x < 0
        0
      else
        (x > 0xFF ? 0xFF : x)
      end
    end

    def to_rgb
      src = components2imagedata
      dst = nil
      pos = -1
      case components.size
      when 1
        # grayscale -> RGB
        dst = "\x00" * width * height * 3
        src.each_byte do |b|
          dst.setbyte(pos += 1, b)
          dst.setbyte(pos += 1, b)
          dst.setbyte(pos += 1, b)
        end
      when 3
        # already in RGB
        dst = src
      when 4
        # CMYK -> RGB
        dst = "\x00" * width * height * 3
        i = -1
        while i < src.size - 1
          c = src.getbyte(i += 1)
          m = src.getbyte(i += 1)
          y = src.getbyte(i += 1)
          k = src.getbyte(i += 1)
          dst.setbyte(pos += 1, 255 - clamp8bit(c * (1 - k / 255.0) + k)) # r
          dst.setbyte(pos += 1, 255 - clamp8bit(m * (1 - k / 255.0) + k)) # g
          dst.setbyte(pos += 1, 255 - clamp8bit(y * (1 - k / 255.0) + k)) # b
        end
      else
        raise "unexpected number of components: #{nc}"
      end
      dst
    end

    def to_rgba
      src = components2imagedata
      dst = "\xff" * width * height * 4
      pos = -1
      case components.size
      when 1
        # grayscale -> RGBA
        src.each_byte do |b|
          dst.setbyte(pos += 1, b)
          dst.setbyte(pos += 1, b)
          dst.setbyte(pos += 1, b)
          pos += 1 # alpha
        end
      when 3
        # RGB -> RGBA
        i = -1
        while i < src.size - 1
          dst.setbyte(pos += 1, src.getbyte(i += 1))
          dst.setbyte(pos += 1, src.getbyte(i += 1))
          dst.setbyte(pos += 1, src.getbyte(i += 1))
          pos += 1 # alpha
        end
      when 4
        # CMYK -> RGBA
        i = -1
        while i < src.size - 1
          c = src.getbyte(i += 1)
          m = src.getbyte(i += 1)
          y = src.getbyte(i += 1)
          k = src.getbyte(i += 1)
          dst.setbyte(pos += 1, 255 - clamp8bit(c * (1 - k / 255.0) + k)) # r
          dst.setbyte(pos += 1, 255 - clamp8bit(m * (1 - k / 255.0) + k)) # g
          dst.setbyte(pos += 1, 255 - clamp8bit(y * (1 - k / 255.0) + k)) # b
          pos += 1 # alpha
        end
      else
        raise "unexpected number of components: #{nc}"
      end
      dst
    end

    def components2imagedata(color_transform: nil)
      enums = components.map { |c| c.to_enum(width, height) }
      result = "\x00" * width * height * components.size
      pos = -1
      nc = components.size
      case nc
      when 1
        # grayscale
        enums[0].each do |g|
          result.setbyte(pos += 1, g)
        end
      when 2
        # ??
        raise "TBD"
      when 3
        # RGB, default color_transform = true
        color_transform = true if color_transform.nil?
        if color_transform
          enums[0].zip(*enums[1..]) do |y, cb, cr|
            r = clamp8bit(y + 1.402 * (cr - 128))
            g = clamp8bit(y - 0.3441363 * (cb - 128) - 0.71413636 * (cr - 128))
            b = clamp8bit(y + 1.772 * (cb - 128))
            result.setbyte(pos += 1, r)
            result.setbyte(pos += 1, g)
            result.setbyte(pos += 1, b)
          end
        else
          enums[0].zip(*enums[1..]) do |r, g, b|
            result.setbyte(pos += 1, r)
            result.setbyte(pos += 1, g)
            result.setbyte(pos += 1, b)
          end
        end
      when 4
        # CMYK, default color_transform = false
        if color_transform.nil?
          app14 = @chunks.find { |c| c.is_a?(APP) && c.tag.is_a?(APP::Adobe) }
          # get from APP14 "Adobe" tag
          color_transform = true if app14.tag.color_transform.to_i > 0
        end
        if color_transform
          enums[0].zip(*enums[1..]) do |y, cb, cr, k|
            c = clamp8bit(y + 1.402 * (cr - 128))
            m = clamp8bit(y - 0.3441363 * (cb - 128) - 0.71413636 * (cr - 128))
            y = clamp8bit(y + 1.772 * (cb - 128))
            result.setbyte(pos += 1, c)
            result.setbyte(pos += 1, m)
            result.setbyte(pos += 1, y)
            result.setbyte(pos += 1, 255 - k)
          end
        else
          enums[0].zip(*enums[1..]) do |c, m, y, k|
            result.setbyte(pos += 1, 255 - c)
            result.setbyte(pos += 1, 255 - m)
            result.setbyte(pos += 1, 255 - y)
            result.setbyte(pos += 1, 255 - k)
          end
        end
      else
        raise "unexpected number of components: #{nc}"
      end
      result
    end

    def components
      @components ||= _decode_components
    end

    def components_data
      components.map { |c| c.decoded_lines.join }
    end

    def _decode_components
      # Huffman tables
      huffman_tables_dc = {}
      huffman_tables_ac = {}
      # quantization tables
      qtables = {}
      chunks.find_all { |c| c.is_a?(DQT) }.each { |c| qtables.merge!(c.tables) }
      frame = @sof.lossless? ? Lossless::Frame.new(@sof) : Frame.new(@sof, qtables)
      reset_interval = nil
      @chunks.each do |chunk|
        case chunk
        when DHT
          # each SOS might have its own DHT
          chunk.tables.each do |id, td|
            tbl = Huffman.new(*td)
            ((id >> 4) == 0 ? huffman_tables_dc : huffman_tables_ac)[id & 15] = tbl
          end
        when DRI
          reset_interval = chunk.reset_interval
        when SOS
          if huffman_tables_dc.empty? && huffman_tables_ac.empty?
            # https://bugzilla.mozilla.org/show_bug.cgi?id=963907
            Huffman.default_tables.each do |id, tbl|
              ((id >> 4) == 0 ? huffman_tables_dc : huffman_tables_ac)[id & 15] = tbl
            end
          end
          sos = chunk
          components = sos.components.map do |idx, table_spec|
            comp = frame.components.find { |c| c.id == idx }
            comp.huffman_table_dc = huffman_tables_dc[table_spec >> 4]
            comp.huffman_table_ac = huffman_tables_ac[table_spec & 15]
            comp
          end
          decoder_class = @sof.lossless? ? Lossless::Decoder : Decoder
          d = decoder_class.new(sos.ecs.data, frame, components, reset_interval, sos.spectral_start, sos.spectral_end,
            sos.successive_approx >> 4, sos.successive_approx & 0x0f)
          d.decode_scan
        end
      end
      frame.components
    end
  end
end

require_relative "jpeg/chunks"
require_relative "jpeg/decoder"
require_relative "jpeg/huffman"
require_relative "jpeg/lossless"
