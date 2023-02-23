# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module BMP
    MAGIC = "BM"
  end
end

require_relative "bmp/chunks"
require_relative "bmp/reader"
