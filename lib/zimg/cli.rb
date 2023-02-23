# frozen_string_literal: true

require 'optparse'
require 'zhexdump'

module ZIMG
  class CLI

    DEFAULT_ACTIONS = %w'info metadata chunks'

    def initialize argv = ARGV
      # hack #1: allow --chunk as well as --chunks
      @argv = argv.map{ |x| x.sub(/^--chunks?/,'--chunk(s)') }

      # hack #2: allow --chunk(s) followed by a non-number, like "zimg --chunks fname.png"
      @argv.each_cons(2) do |a,b|
        if a == "--chunk(s)" && b !~ /^\d+$/
          a<<"=-1"
        end
      end
    end

    def run
      @actions = []
      @options = { :verbose => 0 }
      optparser = OptionParser.new do |opts|
        opts.banner = "Usage: zimg [options] filename.png"
        opts.separator ""

        opts.on("-i", "--info", "General image info (default)"){ @actions << :info }
        opts.on("-c", "--chunk(s) [ID]", Integer, "Show chunks (default) or single chunk by its #") do |id|
          id = nil if id == -1
          @actions << [:chunks, id]
        end
        opts.on("-m", "--metadata", "Show image metadata, if any (default)"){ @actions << :metadata }

        opts.separator ""
        opts.on("-S", "--scanlines", "Show scanlines info"){ @actions << :scanlines }
        opts.on("-P", "--palette", "Show palette"){ @actions << :palette }
        opts.on(      "--colors", "Show colors used"){ @actions << :colors }

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

        opts.separator ""
        opts.on "-A", '--ascii', 'Try to convert image to ASCII (works best with monochrome images)' do
          @actions << :ascii
        end
        opts.on '--ascii-string STRING', 'Use specific string to map pixels to ASCII characters' do |x|
          @options[:ascii_string] = x
          @actions << :ascii
        end
        opts.on "-N", '--ansi', 'Try to display image as ANSI colored text' do
          @actions << :ansi
        end
        opts.on "-2", '--256', 'Try to display image as 256-colored text' do
          @actions << :ansi256
        end
        opts.on "-W", '--wide', 'Use 2 horizontal characters per one pixel' do
          @options[:wide] = true
        end

        opts.separator ""
        opts.on "-v", "--verbose", "Run verbosely (can be used multiple times)" do |v|
          @options[:verbose] += 1
        end
        opts.on "-q", "--quiet", "Silent any warnings (can be used multiple times)" do |v|
          @options[:verbose] -= 1
        end
        opts.on "-I", "--console", "opens IRB console with specified image loaded" do |v|
          @actions << :console
        end
      end

      if (argv = optparser.parse(@argv)).empty?
        puts optparser.help
        return
      end

      @actions = DEFAULT_ACTIONS if @actions.empty?

      argv.each_with_index do |fname,idx|
        if argv.size > 1 && @options[:verbose] >= 0
          puts if idx > 0
          puts "[.] #{fname}".color(:green)
        end
        @fname = fname

        @zimg = load_file fname

        @actions.each do |action|
          if action.is_a?(Array)
            self.send(*action)
          else
            self.send(action)
          end
        end
      end
    rescue Errno::EPIPE
      # output interrupt, f.ex. when piping output to a 'head' command
      # prevents a 'Broken pipe - <STDOUT> (Errno::EPIPE)' message
    end

    def load_file fname
      @img = Image.load fname, :verbose => @options[:verbose]+1
    end

    def info
      puts "[.] image size #{@img.width || '?'}x#{@img.height || '?'}, #{@img.bpp || '?'}bpp"
      puts "[.] palette = #{@img.palette}" if @img.palette
      if @options[:verbose] > 0
        if @img.respond_to?(:imagedata)
          puts "[.] uncompressed imagedata size = #{@img.imagedata_size} bytes"
          _conditional_hexdump(@img.imagedata, 3)
        end
        if @img.respond_to?(:components_data)
          @img.components_data.each_with_index do |c, idx|
            printf "[.] uncompressed component #%d size = %d bytes\n", idx, c.size
            _conditional_hexdump(c, 3)
          end
        end
      end
    end

    def metadata
      return unless @img.metadata && @img.metadata.any?

      puts "[.] metadata:"
      @img.metadata.each do |k,v,h|
        if @options[:verbose] < 2
          if k.size > 512
            puts "[?] key too long (#{k.size}), truncated to 512 chars".yellow
            k = k[0,512] + "..."
          end
          if v.size > 512
            puts "[?] value too long (#{v.size}), truncated to 512 chars".yellow
            v = v[0,512] + "..."
          end
        end
        if h.keys.sort == [:keyword, :text]
          v.gsub!(/[\n\r]+/, "\n"+" "*19)
          printf "    %-12s : %s\n", k, v.gray
        else
          printf "    %s (%s: %s):", k, h[:language], h[:translated_keyword]
          v.gsub!(/[\n\r]+/, "\n"+" "*19)
          printf "\n%s%s\n", " "*19, v.gray
        end
      end
      puts
    end

    def chunks idx=nil
      max_type_len = 0
      unless idx
        max_type_len = @img.chunks.map{ |x| x.type.to_s.size }.max
      end

      @img.chunks.each do |chunk|
        next if idx && chunk.idx != idx
        colored_type = chunk.type.ljust(max_type_len).magenta
        colored_crc =
          if chunk.crc == :no_crc # hack for BMP chunks (they have no CRC)
            ''
          elsif chunk.crc_ok?
            'CRC OK'.green
          else
            'CRC ERROR'.red
          end
        puts "[.] #{chunk.inspect(@options[:verbose]).sub(chunk.type, colored_type)} #{colored_crc}"

        if @options[:verbose] >= 3
          _conditional_hexdump(chunk.export(fix_crc: false))
        else
          _conditional_hexdump(chunk.data)
        end
      end
    end

    def _conditional_hexdump data, v2 = 2
      return unless data

      if @options[:verbose] <= 0
        # do nothing
      elsif @options[:verbose] < v2
        dump = String.new
        sz = 0x20
        ZHexdump.dump(data[0,sz],
                      show_offset: false,
                      tail: data.size > sz ? " + #{data.size-sz} bytes\n" : "\n",
                      output: dump
                     ){ |row| row.insert(0,"    ") }
        puts dump.gray

      elsif @options[:verbose] >= v2
        dump = String.new
        ZHexdump.dump(data, output: dump){ |row| row.insert(0,"    ") }
        puts dump.gray
      end
    end
  end
end
