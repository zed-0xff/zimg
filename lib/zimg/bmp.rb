# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG::BMP
  MAGIC = "BM"
end

require_relative 'bmp/chunks'
require_relative 'bmp/reader'
