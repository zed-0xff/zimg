# frozen_string_literal: true

module ZIMG
  module BMP
    class Color < ZIMG::Color
      # BMP pixels are in perverted^w reverted order - BGR instead of RGB
      def initialize *a
        h = a.last.is_a?(Hash) ? a.pop : {}
        case a.size
        when 3
          # BGR
          super(*a.reverse, h)
        when 4
          # ABGR
          super a[2], a[1], a[0], a[3], h
        else
          super
        end
      end
    end
  end # BMP
end # ZIMG
