# -*- coding:binary; frozen_string_literal: true -*-
require 'stringio'

module ZIMG
  class Image
    attr_reader :width, :height, :bpp, :palette, :metadata, :chunks

    # possible input params:
    #   IO      of opened image file
    #   String  with image file already readed
    #   Hash    of image parameters to create new blank image
    def initialize x, h={}
      @chunks = []
      @verbose =
        case h[:verbose]
        when true;  1
        when false; 0
        else h[:verbose].to_i
        end

      case x
        when IO
          _from_io x
        when String
          _from_io StringIO.new(x)
        when Hash
          _from_hash x
        else
          raise NotSupported, "unsupported input data type #{x.class}"
      end
    end

    def _from_io io
      io.binmode

      hdr = io.read(BMP::MAGIC.size)
      if hdr == BMP::MAGIC
        _read_bmp io
      elsif hdr == JPEG::MAGIC
        extend(JPEG)
        _read io
      else
        hdr << io.read(PNG_HDR.size - BMP::MAGIC.size)
        if hdr == PNG_HDR
          _read_png io
        else
          raise NotSupported, "Unsupported header #{hdr.inspect} in #{io.inspect}"
        end
      end

      unless io.eof?
        offset     = io.tell
        @extradata << io.read
        STDERR.puts "[?] #{@extradata.last.size} bytes of extra data after image end (IEND), offset = 0x#{offset.to_s(16)}".red if @verbose >= 1
      end
    end

    class << self
      # load image from file
      def load fname, h={}
        open(fname,"rb") do |f|
          self.new(f,h)
        end
      end
      alias :load_file :load
      alias :from_file :load # as in ChunkyPNG
    end
  end
end
