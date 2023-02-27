# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    class Colorspace
      # from libjpeg jdapimin.c
      def self.detect components:, jfif:nil, adobe:nil
        case components.size
        when 1
          Grayscale
        when 3
          cids = components.map(&:id)
          case cids
          when [1,2,3]
            YCbCr
          when [0x01, 0x22, 0x23]
            BG_YCC
          when [?R, ?G, ?B]
            RGB
          when [?r, ?g, ?b]
            BG_RGB
          else
            if jfif
              YCbCr # assume it's YCbCr
            elsif adobe
              case adobe.color_transform
              when 0
                RGB
              when 1
                YCbCr
              else
                warn "[?] Unknown Adobe color transform code #{adobe.color_transform}"
                YCbCr
              end
            else
              warn "[?] Unrecognized component IDs #{cids.inspect}, assuming YCbCr"
              YCbCr
            end
          end
        when 4
          cids = components.map(&:id)
          case cids
          when [1,2,3,4]
            YCCK
          when [?C, ?M, ?Y, ?K]
            CMYK
          else
            if adobe
              case adobe.color_transform
              when 0
                CMYK
              when 2
                YCCK
              else
                warn "[?] Unknown Adobe color transform code #{adobe.color_transform}"
                YCCK
              end
            else
              # Unknown IDs and no special markers, assume straight CMYK.
              CMYK
            end
          end
        else
          warn "[?] unexpected number of components: #{components.size}"
          Unknown
        end
      end

      class Grayscale < Colorspace
      end

      class YCbCr < Colorspace
      end

      class YCCK < Colorspace
      end

      class CMYK < Colorspace
      end

      class BG_YCC < Colorspace
      end

      class RGB < Colorspace
      end

      class BG_RGB < Colorspace
      end

      class Unknown < Colorspace
      end
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
      when 3
        # RGB, default color_transform = true
        color_transform = true if color_transform.nil?
        if color_transform
          enums[0].zip(*enums[1..]) do |y, cb, cr|
            cr -= 128
            cb -= 128
            r = clamp8bit(y + 1.402 * cr)
            g = clamp8bit(y - 0.3441363 * cb - 0.71413636 * cr)
            b = clamp8bit(y + 1.772 * cb)
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

  end
end
