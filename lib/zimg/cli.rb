# frozen_string_literal: true

require "optparse"
require "zhexdump"

module ZIMG
  class CLI
    DEFAULT_ACTIONS = %w[info metadata chunks].freeze

    def initialize(argv = ARGV)
      # HACK: #1: allow --chunk as well as --chunks
      @argv = argv.map { |x| x.sub(/^--chunks?/, "--chunk(s)") }

      # HACK: #2: allow --chunk(s) followed by a non-number, like "zimg --chunks fname.png"
      @argv.each_cons(2) do |a, b|
        a << "=-1" if a == "--chunk(s)" && b !~ /^\d+$/
      end
    end

    def run
      @actions = []
      @options = { verbose: 0 }
      optparser = OptionParser.new do |opts|
        opts.banner = "Usage: zimg [options] filename.png"
        opts.separator ""

        opts.on("-i", "--info", "General image info (default)") { @actions << :info }
        opts.on("-c", "--chunk(s) [ID]", Integer, "Show chunks (default) or single chunk by its #") do |id|
          id = nil if id == -1
          @actions << [:chunks, id]
        end
        opts.on("-m", "--metadata", "Show image metadata, if any (default)") { @actions << :metadata }

        opts.separator ""
        opts.on("-S", "--scanlines", "Show scanlines info") { @actions << :scanlines }
        opts.on("-P", "--palette", "Show palette") { @actions << :palette }
        opts.on("--colors", "Show colors used") { @actions << :colors }

        opts.on "-E", "--extract-chunk ID", Integer, "extract a single chunk" do |id|
          @actions << [:extract_chunk, id]
        end
        opts.on "-D", "--imagedata", "dump unpacked Image Data (IDAT) chunk(s) to stdout" do
          @actions << :unpack_imagedata
        end

        opts.separator ""
        opts.on "-C", "--crop GEOMETRY", "crop image, {WIDTH}x{HEIGHT}+{X}+{Y},",
          "puts results on stdout unless --ascii given" do |x|
          @actions << [:crop, x]
        end

        opts.on "-R", "--rebuild NEW_FILENAME", "rebuild image, useful in restoring borked images" do |x|
          @actions << [:rebuild, x]
        end
        opts.on "--compare OTHER_FILENAME", "compare images pixel-by-pixel" do |x|
          @actions << [:compare, x]
        end

        opts.separator ""
        opts.on "-A", "--ascii", "Try to convert image to ASCII (works best with monochrome images)" do
          @actions << :ascii
        end
        opts.on "--ascii-string STRING", "Use specific string to map pixels to ASCII characters" do |x|
          @options[:ascii_string] = x
          @actions << :ascii
        end
        opts.on "-N", "--ansi", "Try to display image as ANSI colored text" do
          @actions << :ansi
        end
        opts.on "-2", "--256", "Try to display image as 256-colored text" do
          @actions << :ansi256
        end
        opts.on "-W", "--wide", "Use 2 horizontal characters per one pixel" do
          @options[:wide] = true
        end

        opts.separator ""
        opts.on "--fail-fast [N]", Integer, "Abort the run after a certain number of failures (1 by default)." do |n|
          @options[:fail_fast] = n || 1
        end
        opts.on("--backtrace", "Enable full backtrace") { @options[:backtrace] = true }

        opts.separator ""
        opts.on "-v", "--verbose", "Run verbosely (can be used multiple times)" do
          @options[:verbose] += 1
        end
        opts.on "-q", "--quiet", "Silent any warnings (can be used multiple times)" do
          @options[:verbose] -= 1
        end
        opts.on "-I", "--console", "opens IRB console with specified image loaded" do
          @actions << :console
        end
      end

      if (argv = optparser.parse(@argv)).empty?
        puts optparser.help
        return
      end

      @actions = DEFAULT_ACTIONS if @actions.empty?

      nfails = 0
      argv.each_with_index do |fname, idx|
        if argv.size > 1 && @options[:verbose] >= 0
          puts if idx > 0
          puts "[.] #{fname}".color(:green)
        end
        unless process_file(fname)
          nfails += 1
          break if @options[:fail_fast] && nfails >= @options[:fail_fast]
        end
      end
      nfails == 0
    end

    def process_file(fname)
      @fname = fname
      @img = load_file fname
      @actions.each do |action|
        if action.is_a?(Array)
          send(*action)
        else
          send(action)
        end
      end
      true
    rescue Errno::EPIPE
      # output interrupt, f.ex. when piping output to a 'head' command
      # prevents a 'Broken pipe - <STDOUT> (Errno::EPIPE)' message
      true
    rescue StandardError => e
      warn "[!] #{e}".red
      if @options[:backtrace]
        e.backtrace.each do |line|
          warn line.red
        end
      end
      false
    end

    def load_file(fname)
      ZIMG.load fname, verbose: @options[:verbose] + 1
    end

    def info
      puts "[.] image size #{@img.width || "?"}x#{@img.height || "?"}, #{@img.bpp || "?"}bpp"
      puts "[.] palette = #{@img.palette}" if @img.palette
      puts "[.] colorspace = #{@img.colorspace}" if @img.respond_to?(:colorspace)
      return unless @options[:verbose] > 0

      if @img.respond_to?(:imagedata)
        puts "[.] uncompressed imagedata size = #{@img.imagedata_size} bytes"
        _conditional_hexdump(@img.imagedata, 3)
      end
      return unless @img.respond_to?(:components_data)

      @img.components_data.each_with_index do |c, idx|
        printf "[.] uncompressed component #%d size = %d bytes\n", idx, c.size
        _conditional_hexdump(c, 3)
      end
    end

    def metadata
      return unless @img.metadata&.any?

      puts "[.] metadata:"
      @img.metadata.each do |k, v, h|
        if @options[:verbose] < 2
          if k.size > 512
            puts "[?] key too long (#{k.size}), truncated to 512 chars".yellow
            k = "#{k[0, 512]}..."
          end
          if v.size > 512
            puts "[?] value too long (#{v.size}), truncated to 512 chars".yellow
            v = "#{v[0, 512]}..."
          end
        end
        if h.keys.sort == %i[keyword text]
          v.gsub!(/[\n\r]+/, "\n#{" " * 19}")
          printf "    %-12s : %s\n", k, v.gray
        else
          printf "    %s (%s: %s):", k, h[:language], h[:translated_keyword]
          v.gsub!(/[\n\r]+/, "\n#{" " * 19}")
          printf "\n%s%s\n", " " * 19, v.gray
        end
      end
      puts
    end

    def chunks(idx = nil)
      max_type_len = 0
      max_type_len = @img.chunks.map { |x| x.type.to_s.size }.max unless idx

      @img.chunks.each do |chunk|
        next if idx && chunk.idx != idx

        colored_type = chunk.type.ljust(max_type_len).magenta
        colored_crc =
          if chunk.crc == :no_crc # HACK: for BMP chunks (they have no CRC)
            ""
          elsif chunk.crc_ok?
            "CRC OK".green
          else
            "CRC ERROR".red
          end
        puts "[.] #{chunk.inspect(@options[:verbose]).sub(chunk.type, colored_type)} #{colored_crc}"

        if @options[:verbose] >= 3
          _conditional_hexdump(chunk.export(fix_crc: false))
        else
          _conditional_hexdump(chunk.data)
        end
      end
    end

    def scanlines
      @img.scanlines.each do |sl|
        p sl # rubocop:disable Lint/Debugger
        case @options[:verbose]
        when 1
          hexdump(sl.raw_data) if sl.raw_data
        when 2
          hexdump(sl.decoded_bytes)
        when 3..999
          hexdump(sl.raw_data) if sl.raw_data
          hexdump(sl.decoded_bytes)
          puts
        end
      end
    end

    def _conditional_hexdump(data, v2 = 2)
      return unless data

      if @options[:verbose] <= 0
        # do nothing
      elsif @options[:verbose] < v2
        dump = String.new
        sz = 0x20
        ZHexdump.dump(data[0, sz],
          show_offset: false,
          tail:        data.size > sz ? " + #{data.size - sz} bytes\n" : "\n",
          output:      dump) { |row| row.insert(0, "    ") }
        puts dump.gray

      elsif @options[:verbose] >= v2
        dump = String.new
        ZHexdump.dump(data, output: dump) { |row| row.insert(0, "    ") }
        puts dump.gray
      end
    end

    def ascii
      @img.height.times do |y|
        @img.width.times do |x|
          c = @img[x, y].to_ascii(*[@options[:ascii_string]].compact)
          c *= 2 if @options[:wide]
          print c
        end
        puts
      end
    end

    def ansi
      spc = @options[:wide] ? "  " : " "
      @img.height.times do |y|
        @img.width.times do |x|
          print spc.background(@img[x, y].to_ansi)
        end
        puts
      end
    end

    def ansi256
      require "rainbow"
      spc = @options[:wide] ? "  " : " "
      @img.height.times do |y|
        @img.width.times do |x|
          print spc.background(@img[x, y].to_html)
        end
        puts
      end
    end

    def compare(other_fname)
      images = [@img, load_file(other_fname)]

      # limit = 100
      alpha_used = images.any?(&:alpha_used?)
      channels = alpha_used ? %w[r g b a] : %w[r g b]

      printf "%6s %4s %4s : %s  ...\n".magenta, "#", "X", "Y", (alpha_used ? "RRGGBBAA" : "RRGGBB")

      idx = ndiff = 0
      images[0].each_pixel do |_c, x, y|
        colors = images.map { |img| img[x, y] }
        if colors.uniq.size > 1
          ndiff += 1
          printf "%6d %4d %4d : ", idx, x, y
          t = Array.new(images.size) { String.new }
          channels.each do |channel|
            values = colors.map { |color| color.send(channel) }
            if values.uniq.size == 1
              # all equal
              values.each_with_index do |value, idx|
                t[idx] << "%02x".gray % value
              end
            else
              # got diff
              values.each_with_index do |value, idx|
                t[idx] << "%02x".red % value
              end
            end
          end
          puts t.join("  ")
        end
        idx += 1
        #        if limit && ndiff >= limit
        #          puts "[.] diff limit #{limit} reached"
        #          break
        #        end
      end
    end

    def console
      ARGV.clear # clear ARGV so IRB is not confused
      require "irb"
      m0 = IRB.method(:setup)
      img = @img

      # override IRB.setup, called from IRB.start
      IRB.define_singleton_method :setup do |*args|
        m0.call(*args)
        conf[:IRB_RC] = proc do |context|
          context.main.instance_variable_set "@img", img
          context.main.define_singleton_method(:img) { @img }
        end
      end

      puts "[.] img = ZPNG::Image.load(#{@fname.inspect})".gray
      IRB.start
    end
  end
end
