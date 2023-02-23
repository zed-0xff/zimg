# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG

    class Chunk
      attr_accessor :marker, :size, :data

      def initialize marker, io
        @marker = marker
        @size = io.read(2).unpack('n')[0]
        @data = io.read(@size-2)
      end

      def type
        r = self.class.name.split("::").last.ljust(4)
        r = "ch_%02X" % @marker[1].ord if r == "Chunk"
        r
      end

      def crc
        :no_crc
      end

      def inspect *args
        size = @size ? sprintf("%6d",@size) : sprintf("%6s","???")
        sprintf "<%4s size=%s >", type, size
      end

      def export *args
        @marker + [@size].pack('n') + @data
      end
    end

    class APP < Chunk
      attr_accessor :name

      # BYTE Version[2];      /* 07h  JFIF Format Revision      */
      # BYTE Units;           /* 09h  Units used for Resolution */
      # BYTE Xdensity[2];     /* 0Ah  Horizontal Resolution     */
      # BYTE Ydensity[2];     /* 0Ch  Vertical Resolution       */
      # BYTE XThumbnail;      /* 0Eh  Horizontal Pixel Count    */
      # BYTE YThumbnail;      /* 0Fh  Vertical Pixel Count      */
      class JFIF < IOStruct.new( 'vcnncc', :version, :units, :xdensity, :ydensity, :xthumbnail, :ythumbnail )
        def inspect *args
          r = "<" + super.split(' ',3).last
          r.sub!(/version=\d+/, "version=#{version >> 8}.#{version & 0xff}") if version
          r
        end
      end

      def initialize marker, io
        super
        @id  = marker[1].ord & 0xf
        @name = @data.unpack('Z*')[0]
        if @name == 'JFIF'
          @jfif = JFIF.read(@data[5..-1])
          # TODO: read thumbnail, see https://en.wikipedia.org/wiki/JPEG_File_Interchange_Format
        end
      end

      def type
        "APP#{@id}"
      end

      def inspect *args
        r = super.chop + ("name=%s >" % name.inspect)
        if @jfif
          r = r.chop + ("jfif=%s>" % @jfif.inspect)
        end
        r
      end
    end

    class SOF < Chunk
      def initialize marker, io
        super
        @id = marker[1].ord & 0xf
      end

      def type
        "SOF#{@id}"
      end
    end

    class SOF012 < SOF
      attr_accessor :bpp, :width, :height, :ncomp, :components
      attr_accessor :color # for compatibility with IHDR

      def initialize marker, io
        super
        @bpp, @height, @width, @ncomp = @data.unpack('CnnC')
        @components = []
        @ncomp.times do |i|
          id, hv, qid = @data[6+i*3, 3].unpack('CCC')
          @components << Component.new(id, hv, qid)
        end
      end

      def extended?
        @id == 1 # SOF1
      end

      def progressive?
        @id == 2 # SOF2
      end

      def inspect verbose = 0
        kind =
          if extended?
            "extended "
          elsif progressive?
            "progressive "
          else
            ""
          end
        r = super.chop + ("%sbpp=%d width=%d height=%d ncomp=%d >" % [kind, bpp, width, height, ncomp])
        r = r.chop + ("components=%s >" % [components.inspect])
        r
      end
    end

    # Define Huffman Table
    class DHT < Chunk
      attr_accessor :id, :tables

      def initialize marker, io
        super
        @tables = {}
        sio = StringIO.new(@data)
        while !sio.eof?
          id, *lengths = sio.read(17).unpack("C*")
          values = sio.read(lengths.inject(:+)).unpack("C*")
          @tables[id] = [lengths, values]
        end
      end

      def inspect verbose = 0
        r = super.chop + ("ids=%s >" % [tables.keys.inspect])
        r = r.chop + ("tables=%s >" % [tables.values.inspect]) if verbose > 0
        r
      end
    end

    # can store multiple tables
    class DQT < Chunk
      attr_accessor :tables

      def initialize marker, io
        super
        @tables = {}
        sio = StringIO.new(@data)
        while !sio.eof?
          id = sio.read(1).unpack("C")[0]
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
          table = [0]*64
          values.each_with_index{ |value, idx| table[DCT_ZIGZAG[idx]] = value }

          @tables[id] = table
        end
      end

      def inspect verbose = 0
        r = super.chop + ("ids=%s >" % tables.keys.inspect)
        r = r.chop + ("tables=%s >" % tables.values.inspect) if verbose > 0
        r
      end
    end

    class DRI < Chunk
      attr_accessor :reset_interval

      def initialize marker, io
        super
        @reset_interval = @data.unpack('n')[0]
      end

      def inspect *args
        super.chop + ("reset_interval=%d >" % reset_interval)
      end
    end

    class SOS < Chunk
      attr_accessor :ncomp, :components, :spectral_start, :spectral_end, :successive_approx
      attr_accessor :ecs

      def initialize marker, io
        super
        sio = StringIO.new(@data)
        @ncomp = sio.read(1).ord
        @components = []
        @ncomp.times do |i|
          @components << [sio.read(1).ord, sio.read(1).ord]
        end
        @spectral_start, @spectral_end, @successive_approx = sio.read(3).unpack('C3')
      end

      def inspect *args
        super.chop + ("ncomp=%d components=%s spectral=%d..%d successive_approx=%d>" % [
          ncomp, components.inspect, spectral_start, spectral_end, successive_approx])
      end
    end

    class DAC < Chunk; end

    class COM < Chunk
      def inspect *args
        super.chop + ("data=%s>" % data.inspect)
      end
    end

    class DNL < Chunk
      attr_accessor :number_of_lines # same as image.height

      def initialize marker, io
        super
        @number_of_lines = @data.unpack('n')[0]
      end

      def inspect *args
        super.chop + ("number_of_lines=%d >" % [number_of_lines])
      end
    end

    # Its length is unknown in advance, nor defined in the file.
    # The only way to get its length is to either decode it or to fast-forward over it:
    # just scan forward for a FF byte. If it's a restart marker (followed by D0 - D7) or a data FF (followed by 00), continue.
    class ECS < Chunk
      def initialize io
        @data = io.read
        if (pos = @data.index(/\xff[^\x00\xd0-\xd7]/))
          io.seek(pos-@data.size, :CUR) # seek back
          @data = @data[0, pos]
        end
        @size = @data.size
      end

      def export *args
        @data
      end
    end

  end
end
