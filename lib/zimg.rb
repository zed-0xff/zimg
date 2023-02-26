# frozen_string_literal: true

module ZIMG
  class Error < StandardError; end
  class NotSupported  < Error; end
  class ArgumentError < Error; end

  module DeepCopyable
    def deep_copy
      Marshal.load(Marshal.dump(self))
    end
  end

  @magics = {}

  class << self
    attr_reader :magics

    def supported_formats
      magics.values.uniq
    end

    def register_format!(fmt)
      m = const_get(fmt.to_s.upcase)
      @magics[m.const_get("MAGIC")] = fmt
    end

    # load image from file
    def load(fname, h = {})
      File.open(fname, "rb") do |f|
        Image.new(f, h)
      end
    end

    def from_rgb(data, width:, height:)
      PNG.from_rgb(data, width: width, height: height)
    end

    def from_rgba(data, width:, height:)
      PNG.from_rgba(data, width: width, height: height)
    end
  end
end

require_relative "zimg/utils/string_ext"

require_relative "zimg/chunk"
require_relative "zimg/color"

require_relative "zimg/png"
require_relative "zimg/bmp"
require_relative "zimg/jpeg"

require_relative "zimg/image"
require_relative "zimg/pixels"
require_relative "zimg/version"
