# -*- coding:binary; frozen_string_literal: true -*-

require "stringio"

module ZIMG
  class Image
    include DeepCopyable

    attr_reader :width, :height, :bpp, :palette, :metadata, :chunks, :format, :color_class, :verbose
    attr_accessor :scanlines

    # possible input params:
    #   IO      of opened image file
    #   String  with image file already readed
    #   Hash    of image parameters to create new blank image
    def initialize(x, h = {})
      @chunks = []
      @color_class = Color
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
        # XXX currently implicitly creates PNG
        extend PNG
        @format = :png
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

      @format = fmt
      m = ZIMG.const_get(fmt.to_s.upcase)
      extend(m)
      send("read_#{fmt}", io)

      return if io.eof?

      offset     = io.tell
      @extradata << io.read
      return unless @verbose >= 1

      warn "[?] #{@extradata.last.size} bytes of extra data after image end (IEND), offset = 0x#{offset.to_s(16)}".red
    end

    # flag that image is just created, and NOT loaded from file
    # as in Rails' ActiveRecord::Base#new_record?
    def new_image?
      @new_image
    end
    alias new? new_image?

    def imagedata_size
      if new_image?
        @scanlines&.map(&:size)&.inject(&:+)
      else
        imagedata&.size
      end
    end

    def ==(other)
      return false unless other.is_a?(Image)
      return false if width  != other.width
      return false if height != other.height

      each_pixel do |c, x, y|
        return false if c != other[x, y]
      end
      true
    end

    def each_pixel(&block)
      e = Enumerator.new do |ee|
        height.times do |y|
          width.times do |x|
            ee.yield(self[x, y], x, y)
          end
        end
      end
      block_given? ? e.each(&block) : e
    end

    def [](x, y)
      scanlines[y][x]
    end

    def inspect
      info =
        %w[format width height bpp colorspace chunks scanlines].map do |k|
          next unless respond_to?(k)

          v = case (v = send(k))
              when Array
                v.empty? ? "[]" : "[#{v.size} entries]"
              when String
                v.size > 40 ? "[#{v.bytesize} bytes]" : v.inspect
              else v.inspect
              end
          "#{k}=#{v}"
        end.compact.join(", ")
      Kernel.format("#<ZIMG::Image %s>", info)
    end

    def to_ascii *args
      scanlines&.map { |l| l.to_ascii(*args) }&.join("\n")
    end

    def pixels
      Pixels.new(self)
    end

    def alpha_used?
      false
    end
  end
end
