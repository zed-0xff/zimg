# frozen_string_literal: true

module ZIMG
  module PNG
    class TextChunk < Chunk
      attr_accessor :keyword, :text

      INTEGER_CLASS = RUBY_VERSION > "2.4" ? Integer : Fixnum # rubocop:disable Lint/UnifiedInteger

      def inspect(verbosity = 10)
        vars = %w[keyword text language translated_keyword cmethod cflag]
        vars -= %w[text translated_keyword] if verbosity <= 0
        info =
          vars.map do |var|
            t = instance_variable_get("@#{var}")
            unless t.is_a?(INTEGER_CLASS)
              t = t.to_s
              t = "#{t[0..20]}..." if t.size > 20
            end
            if t.nil? || t == ""
              nil
            else
              ", #{var.to_s.tr("@", "")}=#{t.inspect}"
            end
          end.compact.join
        "#{super.chop.rstrip}#{info}>"
      end

      def to_hash
        { keyword: keyword, text: text }
      end
    end

    class Chunk
      class TEXT < TextChunk
        def initialize *args
          super
          @keyword, @text = data.unpack("Z*a*")
        end
      end

      class ZTXT < TextChunk
        attr_accessor :cmethod # compression method

        def initialize *args
          super
          @keyword, @cmethod, @text = data.unpack("Z*Ca*")
          # current only @cmethod value is 0 - deflate
          return unless @text

          @text = Zlib::Inflate.inflate(@text)
        end
      end

      class ITXT < TextChunk
        attr_accessor :cflag, :cmethod, :language, :translated_keyword # compression flag & method

        def initialize *args
          super
          # The text, unlike the other strings, is not null-terminated; its length is implied by the chunk length.
          # http://www.libpng.org/pub/png/spec/1.2/PNG-Chunks.html#C.iTXt
          @keyword, @cflag, @cmethod, @language, @translated_keyword, @text = data.unpack("Z*CCZ*Z*a*")
          @text = Zlib::Inflate.inflate(@text) if @cflag == 1 && @cmethod == 0
          if @text
            begin
              @text.force_encoding("utf-8")
            rescue StandardError
              nil
            end
          end
          return unless @translated_keyword

          begin
            @translated_keyword.force_encoding("utf-8")
          rescue StandardError
            nil
          end
        end

        def to_hash
          super.tap do |h|
            h[:language] = @language if @language || !@language.empty?
            h[:translated_keyword] = @translated_keyword if @translated_keyword || !@translated_keyword.empty?
          end
        end
      end
    end
  end
end
