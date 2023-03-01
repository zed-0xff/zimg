# -*- coding:binary; frozen_string_literal: true -*-

# https://exiftool.org/TagNames/JPEG.html

module ZIMG
  module JPEG
    class Chunk
      attr_accessor :marker, :size, :data

      def initialize(marker, io)
        @marker = marker
        @size = io.read(2).unpack1("n")
        @data = io.read(@size - 2) if @size > 2
      end

      def type
        r = self.class.name.split("::").last.ljust(4)
        r = format("ch_%02X", @marker[1].ord) if r == "Chunk"
        r
      end

      def crc
        :no_crc
      end

      def inspect *_args
        size = @size ? format("%6d", @size) : format("%6s", "???")
        format "<%4s size=%s >", type, size
      end

      def export *_args
        @marker + [@size].pack("n") + @data
      end
    end

    class APP < Chunk
      attr_accessor :name, :tag

      # BYTE Version[2];      /* 07h  JFIF Format Revision      */
      # BYTE Units;           /* 09h  Units used for Resolution */
      # BYTE Xdensity[2];     /* 0Ah  Horizontal Resolution     */
      # BYTE Ydensity[2];     /* 0Ch  Vertical Resolution       */
      # BYTE XThumbnail;      /* 0Eh  Horizontal Pixel Count    */
      # BYTE YThumbnail;      /* 0Fh  Vertical Pixel Count      */
      class JFIF < IOStruct.new("vcnncc", :version, :units, :xdensity, :ydensity, :xthumbnail, :ythumbnail)
        def inspect *args
          r = "<#{super.split(" ", 3).last}"
          r.sub!(/version=\d+/, "version=0x#{version.to_s(16)}") if version
          r
        end
      end

      class Adobe < IOStruct.new("cnnc", :version, :flags0, :flags1, :color_transform)
        def inspect *args
          r = "<#{super.split(" ", 3).last}"
          r.sub!(/version=\d+/, "version=0x#{version.to_s(16)}") if version
          r
        end
      end

      def initialize(marker, io)
        super
        @id = marker[1].ord & 0xf
        @name = @data.unpack1("Z*")
        case @name
        when "JFIF"
          # APP0
          @tag = JFIF.read(@data[(@name.size + 1)..])
        when "Adobe"
          # APP14
          @tag = Adobe.read(@data[(@name.size + 1)..])
        end

        # TODO: read thumbnail, see https://en.wikipedia.org/wiki/JPEG_File_Interchange_Format
      end

      def type
        "APP#{@id}"
      end

      def inspect *args
        r = super.chop + format("name=%s >", name.inspect)
        r = r.chop + format("tag=%s>", @tag.inspect) if @tag
        r
      end
    end

    class SOF < Chunk
      attr_accessor :bpp, :width, :height, :ncomp, :components, :color # for compatibility with IHDR

      def initialize(marker, io)
        super
        @id = marker[1].ord & 0xf
        @bpp, @height, @width, @ncomp = @data&.unpack("CnnC")
        @components = []
        component_class = lossless? ? Lossless::Component : Component
        @ncomp&.times do |i|
          id, hv, qid = @data[6 + i * 3, 3].unpack("CCC")
          @components << component_class.new(id, hv, qid)
        end
      end

      def type
        "SOF#{@id}"
      end

      def baseline?
        @id == 0
      end

      def differential?
        [5, 6, 7, 13, 14, 15].include?(@id)
      end

      def progressive?
        coding_process == :progressive
      end

      def lossless?
        coding_process == :lossless
      end

      def coding_process
        case @id
        when 0, 1, 5, 9, 13
          :sequential
        when 2, 6, 10, 14
          :progressive
        when 3, 7, 11, 15
          :lossless
        end
      end

      def entropy_coding
        case @id
        when 0, 1, 2, 3, 5, 6, 7
          :huffman
        when 9, 10, 11, 13, 14, 15
          :arithmetic
        end
      end

      def attributes
        a = []
        a << :baseline if baseline?
        a << :differential if differential?
        a << coding_process
        a << entropy_coding
        a.compact
      end

      def inspect *_params
        super.chop +
          attributes.join(" ") +
          format(" bpp=%s width=%s height=%s ncomp=%s ", bpp, width, height, ncomp) +
          format("components=%s >", components.inspect)
      end
    end

    # Define Huffman Table
    class DHT < Chunk
      attr_accessor :id, :tables

      def initialize(marker, io)
        super
        @tables = {}
        sio = StringIO.new(@data)
        until sio.eof?
          id, *lengths = sio.read(17).unpack("C*")
          values = sio.read(lengths.inject(:+)).unpack("C*")
          @tables[id] = [lengths, values]
        end
      end

      def inspect(verbose = 0)
        r = super.chop + format("ids=%s >", tables.keys.inspect)
        r = r.chop + format("tables=%s >", tables.values.inspect) if verbose > 0
        r
      end
    end

    # can store multiple tables
    class DQT < Chunk
      attr_accessor :tables

      def initialize(marker, io)
        super
        @tables = {}
        sio = StringIO.new(@data)
        until sio.eof?
          id = sio.read(1).unpack1("C")
          values =
            case (id >> 4)
            when 0
              # 8 bit values
              sio.read(64).unpack("C*")
            when 1
              # 16 bit values
              sio.read(128).unpack("n*")
            else
              raise "DQT: invalid table spec #{id}"
            end

          id &= 0x0f
          table = [0] * 64
          values.each_with_index { |value, idx| table[DCT_ZIGZAG[idx]] = value }

          @tables[id] = table
        end
      end

      def inspect(verbose = 0)
        r = super.chop + format("ids=%s >", tables.keys.inspect)
        r = r.chop + format("tables=%s >", tables.values.inspect) if verbose > 0
        r
      end
    end

    class DRI < Chunk
      attr_accessor :reset_interval

      def initialize(marker, io)
        super
        @reset_interval = @data.unpack1("n")
      end

      def inspect *args
        super.chop + format("reset_interval=%d >", reset_interval)
      end
    end

    class SOS < Chunk
      attr_accessor :ncomp, :components, :spectral_start, :spectral_end, :successive_approx, :ecs

      def initialize(marker, io)
        super
        sio = StringIO.new(@data)
        @ncomp = sio.read(1).ord
        @components = []
        @ncomp.times do
          @components << [sio.read(1).ord, sio.read(1).ord]
        end
        @spectral_start, @spectral_end, @successive_approx = sio.read(3).unpack("C3")
      end

      def inspect *args
        super.chop + format("ncomp=%d components=%s spectral=%d..%d successive_approx=%d>", ncomp, components.inspect,
          spectral_start, spectral_end, successive_approx)
      end
    end

    class DAC < Chunk; end

    class COM < Chunk
      def inspect *args
        super.chop + format("data=%s>", data.inspect)
      end
    end

    class DNL < Chunk
      attr_accessor :number_of_lines # same as image.height

      def initialize(marker, io)
        super
        @number_of_lines = @data.unpack1("n")
      end

      def inspect *args
        super.chop + format("number_of_lines=%d >", number_of_lines)
      end
    end

    # Its length is unknown in advance, nor defined in the file.
    # The only way to get its length is to either decode it or to fast-forward over it:
    # just scan forward for a FF byte.
    # If it's a restart marker (followed by D0 - D7) or a data FF (followed by 00), continue.
    class ECS < Chunk
      def initialize(io) # rubocop:disable Lint/MissingSuper
        @data = io.read
        if (pos = @data.index(/\xff[^\x00\xd0-\xd7]/))
          io.seek(pos - @data.size, :CUR) # seek back
          @data = @data[0, pos]
        end
        @size = @data.size
      end

      def export *_args
        @data
      end
    end
  end
end
