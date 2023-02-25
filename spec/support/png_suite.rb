# frozen_string_literal: true

require "English"
module PNGSuite
  PNG_SUITE_URL = "http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz"

  class << self
    attr_accessor :dir

    def init(dir)
      @dir = dir
      if Dir.exist?(dir)
        if Dir[File.join(dir, "*.png")].size > 100
          # already fetched and unpacked
          return
        end
      else
        Dir.mkdir(dir)
      end
      require "open-uri"
      puts "[.] fetching PNG test-suite from #{PNG_SUITE_URL} .. "
      data = URI.open(PNG_SUITE_URL).read # rubocop:disable Security/Open

      fname = File.join(dir, "png_suite.tgz")
      File.binwrite fname, data
      puts "[.] unpacking .. "
      system "tar", "xf", fname, "-C", dir
      raise "cannot unpack #{fname}" unless $CHILD_STATUS.success?
    end

    def each *prefixes
      Dir[File.join(dir, "*.png")].each do |fname|
        next unless prefixes.empty? || prefixes.any? do |p|
                      p[/[*?\[]/] ? File.fnmatch(p, File.basename(fname)) : File.basename(fname).start_with?(p)
                    end

        yield fname
      end
    end

    def each_good(&block)
      Dir[File.join(dir, "[^x]*.png")].each(&block)
    end
  end
end
