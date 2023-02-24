# -*- coding:binary; frozen_string_literal: true -*-

# based on https://github.com/jpeg-js/jpeg-js

module ZIMG
  module JPEG
    class Frame
      attr_accessor :progressive, :scanlines, :samples_per_line, :components
      attr_reader :max_h, :max_v, :mcus_per_line, :mcus_per_column

      def initialize(sof, qtables)
        @progressive      = sof.progressive?
        @scanlines        = sof.height
        @samples_per_line = sof.width
        @components       = sof.components

        # According to the JPEG standard, the sampling factor must be between 1 and 4
        # See https://github.com/libjpeg-turbo/libjpeg-turbo/blob/9abeff46d87bd201a952e276f3e4339556a403a3/libjpeg.txt#L1138-L1146
        @max_h = components.map(&:h).max
        @max_v = components.map(&:v).max
        @mcus_per_line = (samples_per_line / 8.0 / max_h).ceil
        @mcus_per_column = (scanlines / 8.0 / max_v).ceil

        components.each do |c|
          c.prepare(self, qtables)
        end
      end
    end # class Frame

    class Component
      # attributes set from JPEG data
      attr_reader :id, :h, :v, :qid
      # self-calculated values
      attr_reader :blocks_per_line, :blocks_per_column, :blocks, :qtable
      # externally-calculated values
      attr_accessor :huffman_table_ac, :huffman_table_dc, :pred, :scale_x, :scale_y

      def initialize(id, hv, qid)
        @id = id
        @qid = qid # quantization_idx
        @h = hv >> 4
        @v = hv & 0x0f
        raise "Invalid sampling factor, expected values above 0" if @h <= 0 || @v <= 0
      end

      def inspect
        format("<%d %d %d %d>", id, h, v, qid)
      end

      def prepare(frame, qtables)
        @blocks_per_line          = ((frame.samples_per_line / 8.0).ceil * 1.0 * h / frame.max_h).ceil
        @blocks_per_column        = ((frame.scanlines / 8.0).ceil * 1.0 * v / frame.max_v).ceil
        blocks_per_line_for_mcu   = frame.mcus_per_line * h
        blocks_per_column_for_mcu = frame.mcus_per_column * v

        @blocks = []
        blocks_per_column_for_mcu.times do
          row = []
          blocks_per_line_for_mcu.times do
            row.push([0] * 64)
          end
          @blocks.push(row)
        end
        @qtable = qtables[qid]
        raise "no qtable ##{qid}" unless @qtable

        @scale_x = 1.0 * h / frame.max_h
        @scale_y = 1.0 * v / frame.max_v
      end

      def to_enum(width, height)
        Enumerator.new do |e|
          y = 0
          height.times do
            line = decoded_lines[y]
            x = 0
            width.times do
              e << line.getbyte(x)
              x += @scale_x
            end
            y += @scale_y
          end
        end
      end

      def decoded_lines
        @decoded_lines ||= _decode
      end

      def _decode
        samples_per_line = blocks_per_line << 3
        ri = [0] * 64 # Int32
        rb = "\x00" * 64 # Uint8
        lines = []
        blocks_per_column.times do |block_row|
          scanline = block_row << 3
          8.times do
            lines.push("\x00" * samples_per_line)
          end
          blocks_per_line.times do |block_col|
            quantize_and_inverse(blocks[block_row][block_col], rb, ri)

            offset = 0
            sample = block_col << 3
            8.times do |j|
              line = lines[scanline + j]
              8.times do |i|
                line[sample + i] = rb[offset]
                offset += 1
              end
            end
          end
        end
        lines
      end

      DCT_COS_1    = 4017  # cos(pi/16)
      DCT_SIN_1    = 799   # sin(pi/16)
      DCT_COS_3    = 3406  # cos(3*pi/16)
      DCT_SIN_3    = 2276  # sin(3*pi/16)
      DCT_COS_6    = 1567  # cos(6*pi/16)
      DCT_SIN_6    = 3784  # sin(6*pi/16)
      DCT_SQRT_2   = 5793  # sqrt(2)
      DCT_SQRT_2D2 = 2896  # sqrt(2) / 2

      # A port of poppler's IDCT method which in turn is taken from:
      # Christoph Loeffler, Adriaan Ligtenberg, George S. Moschytz,
      # "Practical Fast 1-D DCT Algorithms with 11 Multiplications",
      # IEEE Intl. Conf. on Acoustics, Speech & Signal Processing, 1989, 988-991.
      def quantize_and_inverse(zz, data_out, data_in)
        v0 = v1 = v2 = v3 = v4 = v5 = v6 = v7 = t = 0
        p = data_in

        # dequant
        64.times do |i|
          p[i] = zz[i] * qtable[i]
        end

        # inverse DCT on rows
        8.times do |i|
          row = 8 * i

          # check for all-zero AC coefficients
          if p[1 + row] == 0 && p[2 + row] == 0 && p[3 + row] == 0 &&
             p[4 + row] == 0 && p[5 + row] == 0 && p[6 + row] == 0 &&
             p[7 + row] == 0
            t = (DCT_SQRT_2 * p[0 + row] + 512) >> 10
            p[0 + row] = t
            p[1 + row] = t
            p[2 + row] = t
            p[3 + row] = t
            p[4 + row] = t
            p[5 + row] = t
            p[6 + row] = t
            p[7 + row] = t
            next
          end

          # stage 4
          v0 = (DCT_SQRT_2 * p[0 + row] + 128) >> 8
          v1 = (DCT_SQRT_2 * p[4 + row] + 128) >> 8
          v4 = (DCT_SQRT_2D2 * (p[1 + row] - p[7 + row]) + 128) >> 8
          v7 = (DCT_SQRT_2D2 * (p[1 + row] + p[7 + row]) + 128) >> 8
          v2 = p[2 + row]
          v5 = p[3 + row] << 4
          v6 = p[5 + row] << 4
          v3 = p[6 + row]

          # stage 3
          t = (v0 - v1 + 1) >> 1
          v0 = (v0 + v1 + 1) >> 1
          v1 = t
          t = (v2 * DCT_SIN_6 + v3 * DCT_COS_6 + 128) >> 8
          v2 = (v2 * DCT_COS_6 - v3 * DCT_SIN_6 + 128) >> 8
          v3 = t
          t = (v4 - v6 + 1) >> 1
          v4 = (v4 + v6 + 1) >> 1
          v6 = t
          t = (v7 + v5 + 1) >> 1
          v5 = (v7 - v5 + 1) >> 1
          v7 = t

          # stage 2
          t = (v0 - v3 + 1) >> 1
          v0 = (v0 + v3 + 1) >> 1
          v3 = t
          t = (v1 - v2 + 1) >> 1
          v1 = (v1 + v2 + 1) >> 1
          v2 = t
          t = (v4 * DCT_SIN_3 + v7 * DCT_COS_3 + 2048) >> 12
          v4 = (v4 * DCT_COS_3 - v7 * DCT_SIN_3 + 2048) >> 12
          v7 = t
          t = (v5 * DCT_SIN_1 + v6 * DCT_COS_1 + 2048) >> 12
          v5 = (v5 * DCT_COS_1 - v6 * DCT_SIN_1 + 2048) >> 12
          v6 = t

          # stage 1
          p[0 + row] = v0 + v7
          p[1 + row] = v1 + v6
          p[2 + row] = v2 + v5
          p[3 + row] = v3 + v4
          p[4 + row] = v3 - v4
          p[5 + row] = v2 - v5
          p[6 + row] = v1 - v6
          p[7 + row] = v0 - v7
        end

        # inverse DCT on columns
        8.times do |i|
          col = i

          # check for all-zero AC coefficients
          if p[1 * 8 + col] == 0 && p[2 * 8 + col] == 0 && p[3 * 8 + col] == 0 &&
             p[4 * 8 + col] == 0 && p[5 * 8 + col] == 0 && p[6 * 8 + col] == 0 &&
             p[7 * 8 + col] == 0
            t = (DCT_SQRT_2 * data_in[i + 0] + 8192) >> 14
            p[0 * 8 + col] = t
            p[1 * 8 + col] = t
            p[2 * 8 + col] = t
            p[3 * 8 + col] = t
            p[4 * 8 + col] = t
            p[5 * 8 + col] = t
            p[6 * 8 + col] = t
            p[7 * 8 + col] = t
            next
          end

          # stage 4
          v0 = (DCT_SQRT_2 * p[0 * 8 + col] + 2048) >> 12
          v1 = (DCT_SQRT_2 * p[4 * 8 + col] + 2048) >> 12
          v4 = (DCT_SQRT_2D2 * (p[1 * 8 + col] - p[7 * 8 + col]) + 2048) >> 12
          v7 = (DCT_SQRT_2D2 * (p[1 * 8 + col] + p[7 * 8 + col]) + 2048) >> 12
          v2 = p[2 * 8 + col]
          v5 = p[3 * 8 + col]
          v6 = p[5 * 8 + col]
          v3 = p[6 * 8 + col]

          # stage 3
          t = (v0 - v1 + 1) >> 1
          v0 = (v0 + v1 + 1) >> 1
          v1 = t
          t = (v2 * DCT_SIN_6 + v3 * DCT_COS_6 + 2048) >> 12
          v2 = (v2 * DCT_COS_6 - v3 * DCT_SIN_6 + 2048) >> 12
          v3 = t
          t = (v4 - v6 + 1) >> 1
          v4 = (v4 + v6 + 1) >> 1
          v6 = t
          t = (v7 + v5 + 1) >> 1
          v5 = (v7 - v5 + 1) >> 1
          v7 = t

          # stage 2
          t = (v0 - v3 + 1) >> 1
          v0 = (v0 + v3 + 1) >> 1
          v3 = t
          t = (v1 - v2 + 1) >> 1
          v1 = (v1 + v2 + 1) >> 1
          v2 = t
          t = (v4 * DCT_SIN_3 + v7 * DCT_COS_3 + 2048) >> 12
          v4 = (v4 * DCT_COS_3 - v7 * DCT_SIN_3 + 2048) >> 12
          v7 = t
          t = (v5 * DCT_SIN_1 + v6 * DCT_COS_1 + 2048) >> 12
          v5 = (v5 * DCT_COS_1 - v6 * DCT_SIN_1 + 2048) >> 12
          v6 = t

          # stage 1
          p[0 * 8 + col] = v0 + v7
          p[1 * 8 + col] = v1 + v6
          p[2 * 8 + col] = v2 + v5
          p[3 * 8 + col] = v3 + v4
          p[4 * 8 + col] = v3 - v4
          p[5 * 8 + col] = v2 - v5
          p[6 * 8 + col] = v1 - v6
          p[7 * 8 + col] = v0 - v7
        end

        # convert to 8-bit integers
        64.times do |i|
          sample = 128 + ((p[i] + 8) >> 4)
          data_out[i] = (if sample < 0
                           0
                         else
                           (sample > 0xFF ? 0xFF : sample)
                         end).chr
        end
        data_out
      end
    end

    class Decoder
      # rubocop:disable Metrics/ParameterLists
      def initialize(data, frame, components, reset_interval, spectral_start, spectral_end, successive_prev, successive)
        @components       = components
        @data             = data
        @reset_interval   = reset_interval
        @spectral_end     = spectral_end
        @spectral_start   = spectral_start
        @successive       = successive
        @successive_prev  = successive_prev

        @mcus_per_line    = frame.mcus_per_line
        @mcus_per_column  = frame.mcus_per_column
        @progressive      = frame.progressive

        @successive_ac_state = 0
        @successive_ac_next_value = nil
        @eobrun = 0

        @offset = 0
        @bit_io = _create_enumerator(@data)
      end
      # rubocop:enable Metrics/ParameterLists

      def _create_enumerator(data, offset = 0)
        # printf "[d] offset=%6d  _create_enumerator\n", offset
        Enumerator.new do |e|
          sio = StringIO.new(data)
          sio.seek(offset)

          while (b = sio.getbyte)
            @offset += 1
            if b == 0xff
              # unstuff 0
              b1 = sio.getbyte
              raise "unexpected byte 0x#{b1.to_s(16)} after 0xff" if b1 != 0

              @offset += 1
            end
            # printf "[d] offset=%6d byte=%3d\n", @offset-1, b
            e << (b >> 7)
            e << ((b >> 6) & 1)
            e << ((b >> 5) & 1)
            e << ((b >> 4) & 1)
            e << ((b >> 3) & 1)
            e << ((b >> 2) & 1)
            e << ((b >> 1) & 1)
            e << (b & 1)
          end
          e << nil # EOF
        end
      end

      def receive(length)
        r = 0
        length.times do
          bit = @bit_io.next
          return unless bit

          r = (r << 1) | bit
        end
        r
      end

      def receive_and_extend(length)
        n = receive(length)
        return n if n >= (1 << (length - 1))

        n + (-1 << length) + 1
      end

      def decode_scan
        decode_fn =
          if @progressive
            if @spectral_start == 0
              @successive_prev == 0 ? :decode_dc0 : :decode_dc1
            else
              @successive_prev == 0 ? :decode_ac0 : :decode_ac1
            end
          else
            :decode_baseline
          end
        decode_fn = method(decode_fn)

        mcu = 0
        mcu_expected =
          if @components.size == 1
            @components[0].blocks_per_line * @components[0].blocks_per_column
          else
            @mcus_per_line * @mcus_per_column
          end
        @reset_interval ||= mcu_expected

        while mcu < mcu_expected
          @bit_io ||= _create_enumerator(@data, @offset)

          # reset interval stuff
          @components.each { |c| c.pred = 0 }
          @eobrun = 0

          if @components.size == 1
            component = @components[0]
            @reset_interval.times do
              decode_block(component, decode_fn, mcu)
              mcu += 1
            end
          else
            # printf "[d] offset=%6d here\n", @offset
            @reset_interval.times do
              @components.each do |c|
                c.v.times do |j|
                  c.h.times do |k|
                    decode_mcu(c, decode_fn, mcu, j, k)
                  end
                end
              end
              mcu += 1

              # If we've reached our expected MCU's, stop decoding
              break if mcu == mcu_expected
            end
            # printf "[d] offset=%6d here2\n", @offset
          end

          # printf "[d] offset=%6d here_end\n", @offset
          if mcu == mcu_expected
            # Skip trailing bytes at the end of the scan - until we reach the next marker
            printf "[?] %d extra bytes at end of scan\n".yellow, @data.size - @offset if @offset < @data.size
            while @offset < @data.size
              break if @data[@offset] == "\xFF" && @data[@offset + 1] != "\x00"

              @offset += 1
              @bit_io = nil
            end
          end

          # find marker
          marker = @data[@offset, 2]
          break if marker.nil? || marker.empty? # valid EOF
          raise "got #{marker.inspect} instead of marker" if marker[0] != "\xFF"

          break unless (0xd0..0xd7).include?(marker[1].ord) # RSTx

          @offset += 2
          @bit_io = nil

        end # while

        @offset
      end

      def decode_mcu(component, decode_fn, mcu, row, col)
        # puts "[d] decode_mcu(#{mcu}, #{row}, #{col})"
        mcu_row = mcu / @mcus_per_line
        mcu_col = mcu % @mcus_per_line
        block_row = mcu_row * component.v + row
        block_col = mcu_col * component.h + col
        # skip missing block
        return unless component.blocks[block_row]

        decode_fn.call(component, component.blocks[block_row][block_col])
      end

      def decode_block(component, decode_fn, mcu)
        block_row = mcu / component.blocks_per_line
        block_col = mcu % component.blocks_per_line
        # skip missing block
        return unless component.blocks[block_row]

        decode_fn.call(component, component.blocks[block_row][block_col])
      end

      def decode_baseline(component, dst)
        t = component.huffman_table_dc.decode(@bit_io)
        diff = t == 0 ? 0 : receive_and_extend(t)
        # printf "[d] offset=%6d                       t=%d diff=%d\n", @offset, t, diff
        dst[0] = (component.pred += diff)
        k = 1
        while k < 64
          rs = component.huffman_table_ac.decode(@bit_io)
          s = rs & 15
          r = rs >> 4
          if s == 0
            break if r < 15

            k += 16
            next
          end
          k += r
          z = DCT_ZIGZAG[k]
          dst[z] = receive_and_extend(s)
          k += 1
        end
        # printf "[d] offset=%6d decode_baseline end\n", @offset
      end

      def decode_ac0(component, dst)
        if @eobrun > 0
          @eobrun -= 1
          return
        end
        k = @spectral_start
        e = @spectral_end
        while k <= e
          break unless (rs = component.huffman_table_ac.decode(@bit_io))

          s = rs & 15
          r = rs >> 4
          if s == 0
            if r < 15
              @eobrun = receive(r) + (1 << r) - 1
              break
            end
            k += 16
            next
          end
          k += r
          z = DCT_ZIGZAG[k]
          dst[z] = receive_and_extend(s) * (1 << @successive)
          k += 1
        end
      end

      def decode_ac1(component, dst)
        k = @spectral_start
        e = @spectral_end
        r = 0
        while k <= e
          z = DCT_ZIGZAG[k]
          direction = dst[z] < 0 ? -1 : 1
          case @successive_ac_state
          when 0 # initial state
            rs = component.huffman_table_ac.decode(@bit_io)
            s = rs & 15
            r = rs >> 4
            if s == 0
              if r < 15
                @eobrun = receive(r) + (1 << r)
                @successive_ac_state = 4
              else
                r = 16
                @successive_ac_state = 1
              end
            else
              raise "invalid ACn encoding" if s != 1

              @successive_ac_next_value = receive_and_extend(s)
              @successive_ac_state = r == 0 ? 3 : 2
            end
            next
          when 1, 2 # skipping r zero items
            if dst[z] != 0
              dst[z] += (@bit_io.next << @successive) * direction
            else
              r -= 1
              if r == 0
                @successive_ac_state = @successive_ac_state == 2 ? 3 : 0
              end
            end
          when 3 # set value for a zero item
            if dst[z] != 0
              dst[z] += (@bit_io.next << @successive) * direction
            else
              dst[z] = @successive_ac_next_value << @successive
              @successive_ac_state = 0
            end
          when 4 # eob
            dst[z] += (@bit_io.next << @successive) * direction if dst[z] != 0
          else
            raise "invalid AC state #{@successive_ac_state}"
          end # case
          k += 1
        end # while
        return unless @successive_ac_state == 4

        @eobrun -= 1
        @successive_ac_state = 0 if @eobrun == 0
      rescue NoMethodError => e
        # catch unexpected end of data (partial_progressive.jpg)
        raise unless e.to_s["undefined method `<<' for nil:NilClass"]
        # TODO: show warning
      end

      def decode_dc0(component, dst)
        t = component.huffman_table_dc.decode(@bit_io)
        diff = t == 0 ? 0 : (receive_and_extend(t) << @successive)
        dst[0] = (component.pred += diff)
      end

      def decode_dc1(_component, dst)
        dst[0] |= (@bit_io.next << @successive)
      end
    end
  end
end
