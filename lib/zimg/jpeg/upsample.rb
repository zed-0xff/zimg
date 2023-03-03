# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    # from libjpeg-turbo
    module Upsample
      def h2v1_fancy_upsample(width, height)
        row = [0] * @downsampled_width * 2
        Enumerator.new do |e|
          height.times do |y|
            o = -1
            line = decoded_lines[y]

            # Special case for first column
            invalue = line.getbyte(0)
            row[o += 1] = invalue
            row[o += 1] = ((invalue * 3 + line.getbyte(1) + 2) >> 2)

            1.upto(@downsampled_width - 2) do |x|
              # General case: 3/4 * nearer pixel + 1/4 * further pixel
              invalue = line.getbyte(x) * 3
              row[o += 1] = ((invalue + line.getbyte(x - 1) + 1) >> 2)
              row[o += 1] = ((invalue + line.getbyte(x + 1) + 2) >> 2)
            end

            # Special case for last column
            invalue = line.getbyte(@downsampled_width - 1)
            row[o += 1] = ((invalue * 3 + line.getbyte(@downsampled_width - 2) + 1) >> 2)
            row[o += 1] = invalue

            # maybe yield entire row?
            width.times do |x|
              e << row[x]
            end
          end
        end
      end

      def h2v2_fancy_upsample(width, _height)
        row = [0] * @downsampled_width * 2
        Enumerator.new do |e|
          @downsampled_height.times do |y|
            2.times do |v|
              o = -1
              line0 = decoded_lines[y]
              line1 =
                if v == 0
                  # next nearest is row above
                  decoded_lines[y == 0 ? 0 : (y - 1)]
                else
                  # next nearest is row below
                  # there's actually can be more decoded_lines than downsampled_width
                  decoded_lines[y == @downsampled_height - 1 ? y : (y + 1)]
                end

              thiscolsum = line0.getbyte(0) * 3 + line1.getbyte(0)
              nextcolsum = line0.getbyte(1) * 3 + line1.getbyte(1)
              row[o += 1] = ((thiscolsum * 4 + 8) >> 4)
              row[o += 1] = ((thiscolsum * 3 + nextcolsum + 7) >> 4)
              lastcolsum = thiscolsum
              thiscolsum = nextcolsum

              2.upto(@downsampled_width - 1) do |x|
                nextcolsum = line0.getbyte(x) * 3 + line1.getbyte(x)
                row[o += 1] = ((thiscolsum * 3 + lastcolsum + 8) >> 4)
                row[o += 1] = ((thiscolsum * 3 + nextcolsum + 7) >> 4)
                lastcolsum = thiscolsum
                thiscolsum = nextcolsum
              end

              # Special case for last column
              row[o += 1] = ((thiscolsum * 3 + lastcolsum + 8) >> 4)
              row[o += 1] = ((thiscolsum * 4 + 7) >> 4)

              # maybe yield entire row?
              width.times do |x|
                e << row[x]
              end
            end
          end
        end
      end
    end
  end
end
