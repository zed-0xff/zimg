# -*- coding:binary; frozen_string_literal: true -*-

# https://github.com/corkami/formats/blob/master/image/jpeg.md
# https://docs.fileformat.com/image/jpeg/
# https://www.file-recovery.com/jpg-signature-format.htm
# https://exiftool.org/TagNames/JPEG.html

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
        when 0xc0..0xc2
          @chunks << (chunk = SOF012.new(marker, io))
          @width = chunk.width
          @height = chunk.height
          @bpp = chunk.bpp
          @sof = chunk
        when 0xc4 # overlaps with SOF range!
          @chunks << DHT.new(marker, io)
        when 0xcc # overlaps with SOF range!
          @chunks << DAC.new(marker, io)
        when 0xc1..0xcf
          @chunks << SOF.new(marker, io)
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

    def components_data
      # Huffman tables
      huffman_tables_dc = {}
      huffman_tables_ac = {}
      # quantization tables
      qtables = {}
      chunks.find_all { |c| c.is_a?(DQT) }.each { |c| qtables.merge!(c.tables) }
      frame = Frame.new(@sof, qtables)
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
          sos = chunk
          components = sos.components.map do |idx, table_spec|
            comp = frame.components.find { |c| c.id == idx }
            comp.huffman_table_dc = huffman_tables_dc[table_spec >> 4]
            comp.huffman_table_ac = huffman_tables_ac[table_spec & 15]
            comp
          end
          d = Decoder.new(sos.ecs.data, frame, components, reset_interval, sos.spectral_start, sos.spectral_end,
            sos.successive_approx >> 4, sos.successive_approx & 0x0f)
          d.decode_scan
        end
      end
      frame.components.map(&:decoded_data)
    end
  end
end

require_relative "jpeg/chunks"
require_relative "jpeg/decoder"
require_relative "jpeg/huffman"
