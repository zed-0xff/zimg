# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    class Scanline
      attr_accessor :image, :idx

      def initialize(image, idx)
        @image = image
        @idx = idx
        @bpc = image.bpp / 8 # bytes per component
      end

      def inspect
        format("#<%s idx=%d>", self.class, idx)
      end

      def data
        image.components.map { |c| c.decoded_lines[@idx] }
      end

      # get specific pixel
      # TODO: optimize
      def [](x)
        image.components.map { |c| c.get_scaled(x, @idx) }
      end
    end
  end
end
