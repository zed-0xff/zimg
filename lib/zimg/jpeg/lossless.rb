# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    module Lossless
      class Frame
        attr_accessor :progressive, :scanlines, :samples_per_line, :components
        attr_reader :max_h, :max_v, :mcus_per_line, :mcus_per_column, :width, :height, :precision

        def initialize(sof)
          @precision        = sof.bpp
          @scanlines        = @height = sof.height
          @samples_per_line = @width = sof.width
          @components       = sof.components

          components.each do |c|
            c.prepare(self)
          end
        end
      end

      class Component
        # attributes set from JPEG data
        attr_reader :id, :h, :v, :qid
        # self-calculated values
        attr_reader :results
        # externally-calculated values
        attr_accessor :huffman_table_ac, :huffman_table_dc

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

        def prepare(frame)
          @results = [0] * frame.width * frame.height
        end

        # TODO: optimize
        def decoded_lines
          [@results.pack("C*")]
        end

        def to_enum(_width, _height)
          @results.to_enum
        end
      end

      PREDICTORS = [
        proc { 0 },
        proc { |ra, _rb, _rc| ra },
        proc { |_ra, rb, _rc| rb },
        proc { |_ra, _rb, rc| rc },
        proc { |ra, rb, rc| ra + rb - rc },
        proc { |ra, rb, rc| ra + ((rb - rc) >> 1) },
        proc { |ra, rb, rc| rb + ((ra - rc) >> 1) },
        proc { |ra, rb, _rc| (ra + rb) / 2 }
      ].freeze

      # rubocop:disable Metrics/ParameterLists
      class Decoder
        def initialize(data, frame, components, reset_interval, spectral_start, _spectral_end, _successive_prev,
                       successive)
          @width = frame.width
          @height = frame.height
          @reset_interval = reset_interval == 0 ? nil : reset_interval
          @components = components
          @bit_io = BitEnumerator.new(data)
          @predictor_id = spectral_start
          @predictor = PREDICTORS[@predictor_id]
          @point_transform = successive
          @precision = frame.precision
        end

        def inspect
          "#<Lossless::Decoder>"
        end

        def decode_scan
          diffs = @components.size.times.map { [0] * @width * @height }
          o = 0
          @height.times do
            @width.times do
              raise "TBD" if @reset_interval

              @components.each_with_index do |c, i|
                value = c.huffman_table_dc.decode(@bit_io)
                diff =
                  case value
                  when 0 then 0
                  when 1..15
                    @bit_io.receive_extend(value)
                  when 16
                    32_768
                  else
                    raise "invalid DC difference magnitude category"
                  end
                diffs[i][o] = diff
                o += 1
              end
            end
          end

          if @predictor_id == 1
            # Ra
            @components.each_with_index do |c, i|
              # calculate the top left pixel
              diff = diffs[i][0]
              prediction = 1 << (@precision - @point_transform - 1)
              result = ((prediction + diff) & 0xFFFF) # modulo 2^16
              result = result << @point_transform
              c.results[0] = result

              # calculate leftmost column, using top pixel as predictor
              previous = result
              1.upto(@height - 1) do |mcu_y|
                diff = diffs[i][mcu_y * @width]
                prediction = previous
                result = ((prediction + diff) & 0xFFFF) # modulo 2^16
                result = result << @point_transform
                c.results[mcu_y * @width] = result
                previous = result
              end

              # calculate rows, using left pixel as predictor
              @height.times do |mcu_y|
                1.upto(@width - 1) do |mcu_x|
                  diff = diffs[i][mcu_y * @width + mcu_x]
                  prediction = c.results[mcu_y * @width + mcu_x - 1]
                  result = ((prediction + diff) & 0xFFFF) # modulo 2^16
                  result = result << @point_transform
                  c.results[mcu_y * @width + mcu_x] = result
                end
              end
            end
          else
            ra = [0] * @components.size
            rb = [0] * @components.size
            rc = [0] * @components.size
            @height.times do |mcu_y|
              @width.times do |mcu_x|
                @components.each_with_index do |c, i|
                  diff = diffs[i][mcu_y * @width + mcu_x]
                  ra[i] = c.results[mcu_y * @width + mcu_x - 1] if mcu_x > 0
                  if mcu_y > 0
                    rb[i] = c.results[(mcu_y - 1) * @width + mcu_x]
                    rc[i] = c.results[(mcu_y - 1) * @width + (mcu_x - 1)] if mcu_x > 0
                  end
                  restart = @reset_interval && mcus_left_until_restart == @reset_interval - 1
                  prediction = predict(ra[i], rb[i], rc[i], mcu_x, mcu_y, restart)
                  result = ((prediction + diff) & 0xFFFF) # modulo 2^16
                  c.results[mcu_y * @width + mcu_x] = result << @point_transform
                end
              end
            end
          end
          @bit_io.bytes_left
        end

        def predict(ra, rb, rc, ix, iy, restart)
          if (ix == 0 && iy == 0) || restart
            # start of first line or restart
            if @precision > 1 + @point_transform
              1 << (@precision - @point_transform - 1)
            else
              0
            end
          elsif iy == 0
            # rest of first line
            ra
          elsif ix == 0
            # start of other line
            rb
          else
            @predictor.call(ra, rb, rc)
          end
        end
      end # class Decoder
      # rubocop:enable Metrics/ParameterLists
    end
  end
end
