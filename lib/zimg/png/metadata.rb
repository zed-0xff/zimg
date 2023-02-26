# frozen_string_literal: true

module ZIMG
  module PNG
    class Metadata < Array
      def initialize(img = nil)
        super()
        return unless img

        img.chunks.each do |c|
          next unless c.is_a?(TextChunk)

          self << [c.keyword, c.text, c.to_hash]
        end
      end

      def [] *args
        if args.first.is_a?(String)
          each { |a| return a[1] if a[0] == args.first }
          nil
        else
          super
        end
      end
    end
  end
end
