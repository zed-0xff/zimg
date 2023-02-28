# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    class Scanline
      attr_accessor :image, :idx

      def initialize(image, idx)
        @image = image
        @idx = idx
      end

      def inspect
        format("#<%s idx=%d>", self.class, idx)
      end
    end
  end
end
