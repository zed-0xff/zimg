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
  end
end

require_relative "zimg/utils/string_ext"

require_relative "zimg/chunk"
require_relative "zimg/color"

require_relative "zimg/bmp"
require_relative "zimg/jpeg"

require_relative "zimg/image"
require_relative "zimg/version"
