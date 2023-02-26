# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module PNG
    MAGIC = "\x89PNG\x0d\x0a\x1a\x0a"

    COLOR_GRAYSCALE  = 0  # Each pixel is a grayscale sample
    COLOR_RGB        = 2  # Each pixel is an R,G,B triple.
    COLOR_INDEXED    = 3  # Each pixel is a palette index; a PLTE chunk must appear.
    COLOR_GRAY_ALPHA = 4  # Each pixel is a grayscale sample, followed by an alpha sample.
    COLOR_RGBA       = 6  # Each pixel is an R,G,B triple, followed by an alpha sample.

    def read_png(io)
      prev_chunk = nil
      until io.eof?
        chunk = Chunk.from_stream(io)
        # heuristics
        if prev_chunk&.check(type: true, crc: false) &&
           chunk.check(type: false, crc: false) && chunk.data && _apply_heuristics(io, prev_chunk, chunk)
          redo
        end
        chunk.idx = @chunks.size
        @chunks << chunk
        prev_chunk = chunk
        break if chunk.is_a?(Chunk::IEND)
      end
      return unless palette && hdr && hdr.depth

      palette.max_colors = 2**hdr.depth
    end

    ###########################################################################
    # chunks access

    def ihdr
      @ihdr ||= @chunks.find { |c| c.is_a?(Chunk::IHDR) }
    end
    alias header ihdr
    alias hdr ihdr

    def trns
      # not used "@trns ||= ..." here b/c it will call find() each time of there's no TRNS chunk
      defined?(@trns) ? @trns : (@trns = @chunks.find { |c| c.is_a?(Chunk::TRNS) })
    end

    def plte
      @plte ||= @chunks.find { |c| c.is_a?(Chunk::PLTE) }
    end
    alias palette plte

    ###########################################################################
    # image attributes

    def bpp
      ihdr && @ihdr.bpp
    end

    def width
      ihdr && @ihdr.width
    end

    def height
      ihdr && @ihdr.height
    end

    def interlaced?
      ihdr && @ihdr.interlace != 0
    end

    def alpha_used?
      ihdr && @ihdr.alpha_used?
    end

    def adam7
      @adam7 ||= Adam7Decoder.new(width, height, bpp)
    end

    def [](x, y)
      # extracting this check into a module => +1-2% speed
      x, y = adam7.convert_coords(x, y) if interlaced?
      scanlines[y][x]
    end

    def []=(x, y, newcolor)
      # extracting these checks into a module => +1-2% speed
      decode_all_scanlines
      x, y = adam7.convert_coords(x, y) if interlaced?
      scanlines[y][x] = newcolor
    end

    def imagedata
      @imagedata ||=
        begin
          warn "[?] no image header, assuming non-interlaced RGB".yellow unless ihdr
          data = _imagedata
          data && !data.empty? ? _safe_inflate(data) : ""
        end
    end

    def imagedata=(data)
      @scanlines = nil
      @imagedata = data
    end

    def self.from_rgb(data, width:, height:)
      img = Image.new(width: width, height: height, bpp: 24)
      img.scanlines = height.times.map { |i| Scanline.new(img, i, decoded_bytes: data[width * 3 * i, width * 3]) }
      img
    end

    def self.from_rgba(data, width:, height:)
      img = Image.new(width: width, height: height, bpp: 32)
      img.scanlines = height.times.map { |i| Scanline.new(img, i, decoded_bytes: data[width * 4 * i, width * 4]) }
      img
    end

    def scanlines
      @scanlines ||=
        begin
          r = []
          n = interlaced? ? adam7.scanlines_count : height.to_i
          n.times do |i|
            r << Scanline.new(self, i)
          end
          r.delete_if(&:bad?)
          r
        end
    end

    def _alpha_color(color)
      return nil unless trns

      # For color type 0 (grayscale), the tRNS chunk contains a single gray level value, stored in the format:
      #
      #   Gray:  2 bytes, range 0 .. (2^bitdepth)-1
      #
      # For color type 2 (truecolor), the tRNS chunk contains a single RGB color value, stored in the format:
      #
      #   Red:   2 bytes, range 0 .. (2^bitdepth)-1
      #   Green: 2 bytes, range 0 .. (2^bitdepth)-1
      #   Blue:  2 bytes, range 0 .. (2^bitdepth)-1
      #
      # (If the image bit depth is less than 16, the least significant bits are used and the others are 0)
      # Pixels of the specified gray level are to be treated as transparent (equivalent to alpha value 0);
      # all other pixels are to be treated as fully opaque ( alpha = (2^bitdepth)-1 )

      @alpha_color ||=
        case hdr.color
        when COLOR_GRAYSCALE
          v = trns.data.unpack1("n") & (2**hdr.depth - 1)
          Color.from_grayscale(v, depth: hdr.depth)
        when COLOR_RGB
          a = trns.data.unpack("n3").map { |v| v & (2**hdr.depth - 1) } # rubocop:disable Lint/ShadowingOuterLocalVariable
          Color.new(*a, depth: hdr.depth)
        else
          raise StandardError, "color2alpha only intended for GRAYSCALE & RGB color modes"
        end

      color == @alpha_color ? 0 : (2**hdr.depth - 1)
    end

    def to_ascii *args
      return unless scanlines.any?

      if interlaced?
        height.times.map { |y| width.times.map { |x| self[x, y].to_ascii(*args) }.join }.join("\n")
      else
        scanlines.map { |l| l.to_ascii(*args) }.join("\n")
      end
    end

    def to_rgb
      if hdr.color == COLOR_RGB
        scanlines.map(&:decoded_bytes).join
      else
        r = "\x00" * 3 * width * height
        i = -1
        each_pixel do |p|
          r.setbyte(i += 1, p.r)
          r.setbyte(i += 1, p.g)
          r.setbyte(i += 1, p.b)
        end
        r
      end
    end

    def export(options = {})
      # allow :zlib_level => nil
      options[:zlib_level] = 9 unless options.key?(:zlib_level)

      if options.fetch(:repack, true)
        data = Zlib::Deflate.deflate(scanlines.map(&:export).join, options[:zlib_level])

        idats = @chunks.find_all { |c| c.is_a?(Chunk::IDAT) }
        case idats.size
        when 0
          # add new IDAT
          @chunks << Chunk::IDAT.new(data: data)
        when 1
          idats[0].data = data
        else
          idats[0].data = data
          # delete other IDAT chunks
          @chunks -= idats[1..]
        end
      end

      unless @chunks.last.is_a?(Chunk::IEND)
        # delete old IEND chunk(s) b/c IEND must be the last one
        @chunks.delete_if { |c| c.is_a?(Chunk::IEND) }

        # add fresh new IEND
        @chunks << Chunk::IEND.new
      end

      MAGIC + @chunks.map(&:export).join
    end

    # modifies this image
    def crop!(params)
      decode_all_scanlines

      x, y, h, w = (params[:x] || 0), (params[:y] || 0), params[:height], params[:width]
      raise ArgumentError, "negative params not allowed" if [x, y, h, w].any? { |x| x < 0 }

      # adjust crop sizes if they greater than image sizes
      h = height - y if (y + h) > height
      w = width - x if (x + w) > width
      raise ArgumentError, "negative params not allowed (p2)" if [x, y, h, w].any? { |x| x < 0 }

      # delete excess scanlines at tail
      scanlines[(y + h)..-1] = [] if (y + h) < scanlines.size

      # delete excess scanlines at head
      scanlines[0, y] = [] if y > 0

      # crop remaining scanlines
      scanlines.each { |l| l.crop!(x, w) }

      # modify header
      hdr.height, hdr.width = h, w

      # return self
      self
    end

    # returns new image
    def crop(params)
      decode_all_scanlines
      # deep copy first, then crop!
      deep_copy.crop!(params)
    end

    def metadata
      @metadata ||= Metadata.new(self)
    end

    # returns new deinterlaced image if deinterlaced
    # OR returns self if no need to deinterlace
    def deinterlace
      return self unless interlaced?

      # copy all but 'interlace' header params
      h = Hash[*%w[width height depth color compression filter].map { |k| [k.to_sym, hdr.send(k)] }.flatten]

      # don't auto-add palette chunk
      h[:palette] = nil

      # create new img
      new_img = self.class.new h

      # copy all but hdr/imagedata/end chunks
      chunks.each do |chunk|
        next if chunk.is_a?(Chunk::IHDR)
        next if chunk.is_a?(Chunk::IDAT)
        next if chunk.is_a?(Chunk::IEND)

        new_img.chunks << chunk.deep_copy
      end

      # pixel-by-pixel copy
      each_pixel do |c, x, y|
        new_img[x, y] = c
      end

      new_img
    end

    private

    def _from_hash(h)
      @new_image = true
      @chunks << Chunk::IHDR.new(h)
      if header.palette_used?
        if h.key?(:palette)
          @chunks << h[:palette] if h[:palette]
        else
          @chunks << Chunk::PLTE.new
          palette[0] = h[:background] || h[:bg] || Color::BLACK # add default bg color
        end
      end
      return unless palette && hdr && hdr.depth

      palette.max_colors = 2**hdr.depth
    end

    # we must decode all scanlines before doing any modifications
    # or scanlines decoded AFTER modification of UPPER ones will be decoded wrong
    def decode_all_scanlines
      return if @all_scanlines_decoded || new_image?

      @all_scanlines_decoded = true
      scanlines.each(&:decode!)
    end

    def _imagedata
      data_chunks = @chunks.find_all { |c| c.is_a?(Chunk::IDAT) }
      case data_chunks.size
      when 0
        # no imagedata chunks ?!
        nil
      when 1
        # a single chunk - save memory and return a reference to its data
        data_chunks[0].data
      else
        # multiple data chunks - join their contents
        data_chunks.map(&:data).join
      end
    end

    # unpack zlib,
    # on errors keep going and try to return maximum possible data
    def _safe_inflate(data)
      zi = Zlib::Inflate.new
      pos = 0
      r = String.new
      begin
        # save some memory by not using String#[] when not necessary
        r << zi.inflate(pos == 0 ? data : data[pos..])
        if zi.total_in < data.size
          @extradata << data[zi.total_in..]
          warn "[?] #{@extradata.last.size} bytes of extra data after zlib stream".red if @verbose >= 1
        end
        # decompress OK
      rescue Zlib::BufError, Zlib::DataError, Zlib::NeedDict
        # tried to decompress, but got EOF - need more data
        warn "[!] #{$ERROR_INFO.inspect}".red if @verbose >= -1
        # collect any remaining data in decompress buffer
        r << zi.flush_next_out
      end

      r == "" ? nil : r
    ensure
      zi.close if zi && !zi.closed?
    end

    HEUR_CHUNK_SIZE_RANGE = (-16..16).freeze

    # assume previous chunk size is not right, try to iterate over neighbour data
    def _apply_heuristics(io, prev_chunk, chunk)
      HEUR_CHUNK_SIZE_RANGE.each do |delta|
        next if delta == 0
        next if prev_chunk.data.size + delta < 0

        io.seek(chunk.offset + delta, IO::SEEK_SET)
        potential_chunk = Chunk.new(io)
        next unless potential_chunk.valid?

        warn Kernel.format("[!] heuristics: invalid %s chunk at offset %d, but valid %s at %d. using latter",
          chunk.type.inspect, chunk.offset, potential_chunk.type.inspect, chunk.offset + delta).red
        if delta > 0
          io.seek(chunk.offset, IO::SEEK_SET)
          data = io.read(delta)
          warn "[!] #{delta} extra bytes of data: #{data.inspect}".red
        else
          io.seek(chunk.offset + delta, IO::SEEK_SET)
        end
        return true
      end
      false
    end
  end
end

require_relative "png/adam7_decoder"
require_relative "png/chunks"
require_relative "png/text_chunks"
require_relative "png/metadata"
require_relative "png/scanline"
require_relative "png/scanline_mixins"

ZIMG.register_format! :png
