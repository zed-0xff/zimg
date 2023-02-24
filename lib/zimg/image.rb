# -*- coding:binary; frozen_string_literal: true -*-

require "stringio"

module ZIMG
  class Image
    attr_reader :width, :height, :bpp, :palette, :metadata, :chunks

    # possible input params:
    #   IO      of opened image file
    #   String  with image file already readed
    #   Hash    of image parameters to create new blank image
    def initialize(x, h = {})
      @chunks = []
      @extradata = []
      @verbose =
        case h[:verbose]
        when true then  1
        when false then 0
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

    def _from_io(io)
      io.binmode

      fmt = nil
      hdr = String.new
      ZIMG.magics.keys.sort_by(&:size).each do |magic|
        hdr << io.read(magic.size - hdr.size) if magic.size > hdr.size
        if hdr == magic
          fmt = ZIMG.magics[magic]
          break
        end
      end

      raise NotSupported, "Unsupported header #{hdr.inspect} in #{io.inspect}" unless fmt

      m = ZIMG.const_get(fmt.to_s.upcase)
      extend(m)
      _read io

      return if io.eof?

      offset     = io.tell
      @extradata << io.read
      return unless @verbose >= 1

      warn "[?] #{@extradata.last.size} bytes of extra data after image end (IEND), offset = 0x#{offset.to_s(16)}".red
    end

    def inspect
      info =
        %w[width height bpp chunks scanlines].map do |k|
          next unless respond_to?(k)

          v = case (v = send(k))
              when Array
                "[#{v.size} entries]"
              when String
                v.size > 40 ? "[#{v.bytesize} bytes]" : v.inspect
              else v.inspect
              end
          "#{k}=#{v}"
        end.compact.join(", ")
      format("#<ZIMG::Image %s>", info)
    end

    class << self
      # load image from file
      def load(fname, h = {})
        File.open(fname, "rb") do |f|
          new(f, h)
        end
      end
      alias load_file load
      alias from_file load # as in ChunkyPNG
    end
  end
end
