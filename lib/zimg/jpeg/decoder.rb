# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    class Frame
      attr_accessor :progressive, :height, :width, :components
      attr_reader :max_h, :max_v, :mcus_per_line, :mcus_per_column

      def initialize(sof, qtables)
        @width       = sof.width
        @height      = sof.height
        @progressive = sof.progressive?
        @components  = sof.components

        # According to the JPEG standard, the sampling factor must be between 1 and 4
        # See https://github.com/libjpeg-turbo/libjpeg-turbo/blob/9abeff46d87bd201a952e276f3e4339556a403a3/libjpeg.txt#L1138-L1146
        @max_h = components.map(&:h).max
        @max_v = components.map(&:v).max
        @mcus_per_line = (width / 8.0 / max_h).ceil
        @mcus_per_column = (height / 8.0 / max_v).ceil

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

      include IDCT
      include Upsample

      def initialize(id, hv, qid)
        @id = id
        @qid = qid # quantization_idx
        @h = hv >> 4
        @v = hv & 0x0f
        raise "Invalid sampling factor, expected values above 0" if @h <= 0 || @v <= 0
      end

      def inspect
        format("<%d %dx%d %d>", id, h, v, qid)
      end

      def prepare(frame, qtables)
        @downsampled_width        = (1.0 * frame.width * h / frame.max_h).ceil
        @downsampled_height       = (1.0 * frame.height * v / frame.max_v).ceil
        @blocks_per_line          = ((frame.width / 8.0).ceil * 1.0 * h / frame.max_h).ceil
        @blocks_per_column        = ((frame.height / 8.0).ceil * 1.0 * v / frame.max_v).ceil
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
        if @downsampled_width > 2
          if @scale_x == 0.5
            return h2v2_fancy_upsample(width, height) if @scale_y == 0.5
            return h2v1_fancy_upsample(width, height) if @scale_y == 1
          end
        elsif @scale_x == 1 && @scale_y == 0.5
          # TODO: implement & test
          return h1v2_fancy_upsample(width, height)
        end

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

      # not upsampled but scaled
      def get_scaled(x, y)
        decoded_lines[y * @scale_y].getbyte(x * @scale_x)
      end

      def decoded_lines
        @decoded_lines ||= _decode(8, 8)
      end

      def _decode(w, h)
        workspace =    [0] * (w * h) # Int32
        result    = "\x00" * (w * h) # Uint8
        method    = "jpeg_idct_#{w}x#{h}".to_sym

        samples_per_line = blocks_per_line * w
        lines = []
        blocks_per_column.times do |block_row|
          scanline = block_row * w
          h.times do
            lines.push("\x00" * samples_per_line)
          end
          blocks_per_line.times do |block_col|
            send(method, blocks[block_row][block_col], result, workspace)
            offset = 0
            sample = block_col * w
            h.times do |j|
              line = lines[scanline + j]
              line[sample, w] = result[offset, w]
              offset += w
            end
          end
        end
        lines
      end
    end

    class BitEnumerator
      def initialize(data, offset: 0)
        @data = data
        @offset = offset
        @eof = false
      end

      def next
        @bio ||= _create_enumerator(@data, @offset)
        @bio.next
      end

      def eof?
        @eof
      end

      def peek_byte(add = 0)
        @data[@offset + add]
      end

      def peek_bytes(n)
        @data[@offset, n]
      end

      def skip_bytes(n)
        @offset += n
        @bio = nil
      end

      def bytes_left
        @data.size - @offset
      end

      def reset!
        @bio = nil
      end

      def receive(length)
        @bio ||= _create_enumerator(@data, @offset)
        r = 0
        length.times do
          bit = @bio.next
          # return unless bit

          r = (r << 1) | bit
        end
        r
      end

      def receive_extend(length)
        n = receive(length)
        return n if n >= (1 << (length - 1))

        n + (-1 << length) + 1
      end

      private

      def _create_enumerator(data, offset = 0)
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
            # printf("[d] byte: %02x, offset: %6d\n", b, @offset-1)
            e << (b >> 7)
            e << ((b >> 6) & 1)
            e << ((b >> 5) & 1)
            e << ((b >> 4) & 1)
            e << ((b >> 3) & 1)
            e << ((b >> 2) & 1)
            e << ((b >> 1) & 1)
            e << (b & 1)
          end
          @eof = true
          # stuff zeroes into the data stream, so that we can produce some kind of image.
          loop do
            e << 0
          end
          # will raise StopIteration if try to read behind at this point
        end
      end
    end

    class Decoder
      # rubocop:disable Metrics/ParameterLists
      def initialize(data, frame, components, reset_interval, spectral_start, spectral_end, ah, al)
        @components       = components
        @reset_interval   = reset_interval
        @spectral_end     = spectral_end
        @spectral_start   = spectral_start
        @al = al
        @ah = ah

        @mcus_per_line    = frame.mcus_per_line
        @mcus_per_column  = frame.mcus_per_column
        @progressive      = frame.progressive

        @offset = 0
        @bit_io = BitEnumerator.new(data)
      end
      # rubocop:enable Metrics/ParameterLists

      def decode_scan
        @successive_ac_state = 0

        decode_fn =
          if @progressive
            if @spectral_start == 0
              @ah == 0 ? :decode_mcu_DC_first : :decode_mcu_DC_refine
            else
              @ah == 0 ? :decode_mcu_AC_first : :decode_mcu_AC_refine
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
          @bit_io.reset!

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
          end

          loop do
            marker = @bit_io.peek_bytes(2)
            case marker
            when "\xFF\xD0".."\xFF\xD7"
              # RSTx
              @bit_io.skip_bytes(2)
              break
            when "\xFF\x00"
              # stuffed 0
              @bit_io.skip_bytes(2)
            when "\xFF\xFF"
              # maybe a series of FF's followed by 0
              @bit_io.skip_bytes(1)
            when nil, ""
              # EOF?
              # return @offset
              break
            else
              warn "[?] expected RSTx, but got #{marker.inspect}"
              return @offset
            end
          end
        end # while

        @offset
      end

      def decode_mcu(component, decode_fn, mcu, row, col)
        # If we've run out of data, just leave the MCU set to zeroes.
        # This way, we return uniform gray for the remainder of the segment.
        return if @bit_io.eof?

        mcu_row = mcu / @mcus_per_line
        mcu_col = mcu % @mcus_per_line
        block_row = mcu_row * component.v + row
        block_col = mcu_col * component.h + col

        decode_fn.call(component, component.blocks[block_row][block_col])
      rescue StopIteration
        # catch unexpected end of data (partial_progressive.jpg, non-interleaved_progressive-*.jpg)
        warn "[?] unexpected EOF"
      end

      def decode_block(component, decode_fn, mcu)
        block_row = mcu / component.blocks_per_line
        block_col = mcu % component.blocks_per_line

        if @bit_io.eof?
          # If we've run out of data, just leave the MCU set to zeroes.
          # This way, we return uniform gray for the remainder of the segment.
        else
          decode_fn.call(component, component.blocks[block_row][block_col])
        end
      rescue StopIteration
        # catch unexpected end of data (partial_progressive.jpg, non-interleaved_progressive-*.jpg)
        warn "[?] unexpected EOF"
      end

      def decode_baseline(component, dst)
        t = component.huffman_table_dc.decode(@bit_io)
        diff = t == 0 ? 0 : @bit_io.receive_extend(t)
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
          dst[z] = @bit_io.receive_extend(s)
          k += 1
        end
      end

      def decode_mcu_AC_first(component, dst)
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
              @eobrun = @bit_io.receive(r) + (1 << r) - 1
              break
            end
            # r == 15
            k += 16
            next
          end
          # s > 0
          k += r
          z = DCT_ZIGZAG[k]
          dst[z] = @bit_io.receive_extend(s) * (1 << @al)
          k += 1
        end
      end

      def decode_mcu_AC_refine(component, dst)
        next_value = nil
        k = @spectral_start
        e = @spectral_end
        r = 0
        z = 0
        while k <= e
          z = DCT_ZIGZAG[k]
          direction = dst[z] < 0 ? -1 : 1
          case @successive_ac_state
          when 0 # initial state
            rs = component.huffman_table_ac.decode(@bit_io)
            s = rs & 15
            r = rs >> 4
            case s
            when 0
              if r < 15
                @eobrun = @bit_io.receive(r) + (1 << r)
                @successive_ac_state = 4
              else
                r = 16
                @successive_ac_state = 1
              end
            when 1
              next_value = @bit_io.receive_extend(1)
              @successive_ac_state = r == 0 ? 3 : 2
            else
              raise "invalid ACn encoding" # libjpeg-turbo: "Corrupt JPEG data: bad Huffman code"
            end
            next
          when 1, 2 # skipping r zero items
            if dst[z] != 0
              dst[z] += (@bit_io.next << @al) * direction
            else
              r -= 1
              if r == 0
                @successive_ac_state = @successive_ac_state == 2 ? 3 : 0
              end
            end
          when 3 # set value for a zero item
            if dst[z] != 0
              dst[z] += (@bit_io.next << @al) * direction
            else
              dst[z] = next_value << @al
              @successive_ac_state = 0
            end
          when 4 # eob
            dst[z] += (@bit_io.next << @al) * direction if dst[z] != 0
          else
            raise "invalid AC state #{@successive_ac_state}"
          end # case
          k += 1
        end # while

        # corresponds to "Output newly nonzero coefficient" line of jdphuff.c
        # (samples/jpeg/jpeg-decoder/tests/reftest/images/partial_progressive.jpg)
        if @successive_ac_state == 3 && next_value && z < 64
          dst[z] = next_value << @al
          next_value = nil
        end

        return unless @successive_ac_state == 4

        @eobrun -= 1
        @successive_ac_state = 0 if @eobrun == 0
      end

      def decode_mcu_DC_first(component, dst)
        t = component.huffman_table_dc.decode(@bit_io)
        diff = t == 0 ? 0 : (@bit_io.receive_extend(t) << @al)
        dst[0] = (component.pred += diff)
      end

      def decode_mcu_DC_refine(_component, dst)
        dst[0] |= (@bit_io.next << @al)
      end
    end # class Decoder
  end
end
