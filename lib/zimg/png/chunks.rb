# -*- coding:binary; frozen_string_literal: true -*-

require "zlib"

module ZIMG
  module PNG
    class Chunk
      attr_accessor :size, :type, :data, :crc, :idx, :offset

      KNOWN_TYPES = %w[IHDR PLTE IDAT IEND cHRM gAMA iCCP sBIT sRGB bKGD hIST tRNS pHYs sPLT tIME iTXt tEXt zTXt].freeze
      VALID_SIZE_RANGE = (0..((2**31) - 1)).freeze

      include DeepCopyable

      def self.from_stream(io)
        _size, type = io.read(8).unpack("Na4")
        io.seek(-8, IO::SEEK_CUR)
        begin
          if const_defined?(type.upcase)
            klass = const_get(type.upcase)
            return klass.new(io)
          end
        rescue NameError
          # invalid chunk type?
        end
        # putting this out of rescue makes better non-confusing exception messages
        # if exception occurs somewhere in Chunk.new
        Chunk.new(io)
      end

      def initialize(x = {})
        if x.respond_to?(:read)
          # IO
          @offset = x.tell
          @size, @type = x.read(8).unpack("Na4")
          begin
            @data = x.read(size)
          rescue Errno::EINVAL
            # TODO: show warning?
            @data = x.read if size > VALID_SIZE_RANGE.end
          end
          @crc         = x.read(4).to_s.unpack1("N")
        elsif x.respond_to?(:[])
          # Hash
          %w[size type data crc].each do |k|
            instance_variable_set "@#{k}", x[k.to_sym]
          end
          if !@type && is_a?(Chunk)
            # guess @type from self class name, e.g. ZPNG::Chunk::IHDR => "IHDR"
            @type = self.class.to_s.split("::").last
          end
          if !@size && @data
            # guess @size from @data
            @size = @data.size
          end
        end
      end

      def export(fix_crc: true)
        @data = export_data # virtual
        @size = @data.size # XXX hmm.. is it always is?
        fix_crc! if fix_crc
        [@size, @type].pack("Na4") + @data + [@crc].pack("N")
      end

      def export_data
        # STDERR.puts "[!] Chunk::#{type} must realize 'export_data' virtual method".yellow if @size != 0
        @data || ""
      end

      def inspect(_verbosity = 10)
        size = @size ? format("%6d", @size) : format("%6s", "???")
        crc  = @crc  ? format("%08x", @crc) : format("%8s", "???")
        type = @type.to_s.gsub(/[^0-9a-z]/i) { |x| format("\\x%02X", x.ord) }
        format "<Chunk #%02d %4s size=%s, crc=%s >", idx.to_i, type, size, crc
      end

      def crc_ok?
        expected_crc = Zlib.crc32(data, Zlib.crc32(type))
        expected_crc == crc
      end

      def check(checks = { type: true, crc: true, size: true })
        checks.each do |check_type, check_mode|
          case check_type
          when :type
            return false if check_mode != KNOWN_TYPES.include?(type)
          when :crc
            return false if check_mode != crc_ok?
          when :size
            return false if check_mode != VALID_SIZE_RANGE.include?(size)
          end
        end
        true
      end

      def valid?
        check
      end

      def fix_crc!
        @crc = Zlib.crc32(data, Zlib.crc32(type))
      end

      class IHDR < Chunk
        attr_accessor :width, :height, :depth, :color, :compression, :filter, :interlace

        SIZE = 13
        FORMAT = "NNC5"

        PALETTE_USED = 1
        COLOR_USED   = 2
        ALPHA_USED   = 4

        SAMPLES_PER_COLOR = {
          COLOR_GRAYSCALE => 1,
          COLOR_RGB => 3,
          COLOR_INDEXED => 1,
          COLOR_GRAY_ALPHA => 2,
          COLOR_RGBA => 4,
        }.freeze

        # http://www.w3.org/TR/PNG/#table111
        ALLOWED_DEPTHS = {
          COLOR_GRAYSCALE => [1, 2, 4, 8, 16],
          COLOR_RGB => [8, 16],
          COLOR_INDEXED => [1, 2, 4, 8],
          COLOR_GRAY_ALPHA => [8, 16],
          COLOR_RGBA => [8, 16],
        }.freeze

        def initialize(x)
          super
          vars = %w[width height depth color compression filter interlace] # order is important
          if x.respond_to?(:read)
            # IO
          elsif x.respond_to?(:[])
            # Hash
            vars.each { |k| instance_variable_set "@#{k}", x[k.to_sym] }

            raise "[!] width not set" unless @width
            raise "[!] height not set" unless @height

            # allow easier image creation like
            # img = Image.new :width => 16, :height => 16, :bpp => 4, :color => false
            # img = Image.new :width => 16, :height => 16, :bpp => 1, :color => true
            # img = Image.new :width => 16, :height => 16, :bpp => 32
            if x[:bpp]
              unless [true, false, nil].include?(@color)
                raise "[!] :color must be either 'true' or 'false' when :bpp is set"
              end
              raise "[!] don't use :depth when :bpp is set" if @depth

              @color, @depth = case x[:bpp]
                               when 1, 2, 4, 8 then [@color ? COLOR_INDEXED : COLOR_GRAYSCALE, x[:bpp]]
                               when 16
                                 raise "[!] I don't know how to make COLOR 16 bpp PNG. do you?" if @color

                                 [COLOR_GRAY_ALPHA, 8]
                               when 24 then      [COLOR_RGB,  8]
                               when 32 then      [COLOR_RGBA, 8]
                               else
                                 raise "[!] unsupported bpp=#{x[:bpp].inspect}"
                               end
            end

            @color       ||= COLOR_RGBA
            @depth       ||= 8
            @compression ||= 0
            @filter      ||= 0
            @interlace   ||= 0

            unless ALLOWED_DEPTHS[@color]&.include?(@depth)
              raise "[!] invalid color mode (#{@color.inspect}) / bit depth (#{@depth.inspect}) combination"
            end
          end
          return unless data

          data.unpack(FORMAT).each_with_index do |value, idx|
            instance_variable_set "@#{vars[idx]}", value
          end
        end

        def export_data
          [@width, @height, @depth, @color, @compression, @filter, @interlace].pack(FORMAT)
        end

        # bits per pixel
        def bpp
          spc = SAMPLES_PER_COLOR[@color]
          spc ? spc * depth : nil
        end

        def color_used?
          (@color & COLOR_USED) != 0
        end

        def grayscale?
          !color_used?
        end

        def palette_used?
          (@color & PALETTE_USED) != 0
        end

        def alpha_used?
          (@color & ALPHA_USED) != 0
        end

        def inspect(verbosity = 10)
          vars = instance_variables - %i[@type @crc @data @size]
          vars -= [:@idx] if verbosity <= 0
          info = vars.map { |var| ", #{var.to_s.tr("@", "")}=#{instance_variable_get(var)}" }.join
          "#{super.chop.rstrip}#{info} >"
        end
      end

      class PLTE < Chunk
        attr_accessor :max_colors

        def [](idx)
          rgb = @data[idx * 3, 3]
          rgb && Color.new(*rgb.unpack("C3"))
        end

        def []=(idx, color)
          @data ||= ""
          @data[idx * 3, 3] = [color.r, color.g, color.b].pack("C3")
        end

        def ncolors
          @data.to_s.size / 3
        end

        # colors enumerator
        def each
          ncolors.times do |i|
            yield self[i]
          end
        end

        # colors enumerator with index
        def each_with_index
          ncolors.times do |i|
            yield self[i], i
          end
        end

        # convert to array of colors
        def to_a
          ncolors.times.map { |i| self[i] }
        end

        def index(color)
          ncolors.times do |i|
            c = self[i]
            return i if c.r == color.r && c.g == color.g && c.b == color.b
          end
          nil
        end

        def add(color)
          raise "palette full (#{ncolors}), cannot add #{color.inspect}" if ncolors >= max_colors

          idx = ncolors
          self[idx] = color
          idx
        end

        def find_or_add(color)
          index(color) || add(color)
        end
        alias << find_or_add
      end

      class CHRM < Chunk
        SIZE = 32
      end

      class GAMA < Chunk
        SIZE = 4
      end

      class IDAT < Chunk; end

      class TIME < Chunk
        SIZE = 7
      end

      class IEND < Chunk
        SIZE = 4
      end

      class PHYS < Chunk
        SIZE = 9
      end

      class SRGB < Chunk
        SIZE = 1
      end

      class TRNS < Chunk; end
    end
  end
end
