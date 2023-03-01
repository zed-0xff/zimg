# frozen_string_literal: true

RSpec.describe "upsample" do
  describe "h2v2_fancy_upsample" do
    let(:encoded_input) do
      input.each_slice(downsampled_width).map { |x| x.map(&:chr).join }
    end

    let(:upsampled_width) { downsampled_width * 2 }

    # from libjpeg-turbo/release/extraneous-data.jpg
    describe "8x8 => 16x16" do
      let(:downsampled_width) { 8 }

      describe "Cb" do
        let(:input) do
          [
            6, 12, 18, 23, 30, 34, 40, 48,
            17,  22,  29,  34,  40,  45,  53, 74,
            28,  34,  39,  45,  51,  59,  78, 100,
            39,  45,  50,  56,  64,  84, 105, 128,
            50,  56,  61,  70,  89, 111, 133, 155,
            61,  67,  75,  95, 116, 138, 160, 183,
            72,  80,  99, 122, 144, 166, 187, 210,
            85, 105, 127, 149, 171, 193, 215, 237
          ]
        end

        let(:output) do
          [
            6, 7, 11, 13, 17, 19, 22, 25, 28, 31, 33, 35, 39, 42, 46, 48,
            9, 10, 13, 16, 19, 22, 25, 27, 31, 34, 36, 38, 42, 46, 52, 54,
            14,  16,  18,  21,  25,  27,  30,  33,  36,  39,  41,  44,  48,  54,  63,  67,
            20,  21,  24,  27,  30,  33,  35,  38,  41,  44,  47,  51,  57,  65,  75,  80,
            25,  27,  30,  32,  35,  38,  41,  44,  47,  50,  54,  60,  68,  77,  88,  93,
            31,  32,  35,  38,  41,  43,  46,  49,  53,  57,  63,  70,  80,  90, 101, 107,
            36,  38,  41,  43,  46,  49,  52,  55,  59,  65,  74,  83,  93, 104, 115, 121,
            42,  43,  46,  49,  52,  54,  58,  62,  68,  75,  86,  96, 107, 118, 129, 135,
            47,  49,  52,  54,  57,  60,  64,  71,  79,  88,  99, 110, 121, 132, 143, 148,
            53,  54,  57,  60,  63,  67,  73,  81,  91, 101, 112, 123, 134, 145, 156, 162,
            58,  60,  63,  66,  70,  76,  84,  94, 104, 115, 126, 137, 148, 159, 170, 176,
            64,  65,  69,  73,  78,  86,  97, 107, 118, 128, 140, 150, 161, 172, 184, 190,
            69,  71,  75,  81,  89,  99, 110, 121, 132, 142, 154, 164, 175, 186, 198, 203,
            75,  78,  84,  91, 101, 112, 123, 134, 145, 156, 167, 178, 189, 200, 211, 217,
            82,  86,  95, 104, 115, 126, 137, 148, 159, 170, 181, 192, 203, 214, 225, 230,
            85,  90, 100, 110, 122, 132, 144, 154, 166, 176, 188, 198, 210, 220, 232, 237
          ]
        end

        it "works" do
          c = ZIMG::JPEG::Component.new(0, 0x11, 0)
          c.instance_variable_set("@decoded_lines", encoded_input)
          c.instance_variable_set("@downsampled_width", downsampled_width)
          c.instance_variable_set("@downsampled_height", input.size / downsampled_width)
          expect(c.h2v2_fancy_upsample(16, 16).to_a).to eq(output)
        end
      end

      describe "Cr" do
        let(:input) do
          [
            147, 132, 114, 98, 81, 66, 48, 32,
            161, 145, 128, 112, 95, 79, 62, 43,
            175, 160, 141, 126, 108, 93, 74, 55,
            189, 173, 157, 140, 123, 104,  85,  66,
            203, 187, 170, 153, 134, 115,  96,  77,
            216, 202, 183, 165, 146, 126, 107,  88,
            230, 214, 195, 175, 157, 137, 118,  99,
            244, 225, 207, 187, 167, 149, 129, 110
          ]
        end

        let(:output) do
          [
            147, 143, 136, 127, 119, 110, 102, 94, 85, 77, 70, 61, 53, 44, 36, 32,
            151, 147, 139, 131, 122, 113, 106, 97, 89, 81, 73, 65, 56, 47, 39, 35,
            158, 154, 146, 137, 129, 120, 113, 104, 96, 88, 80, 71, 63, 54, 45, 40,
            165, 161, 153, 144, 136, 127, 119, 111, 103, 94, 86, 78, 69, 60, 51, 46,
            172, 168, 160, 152, 142, 134, 126, 118, 109, 101, 93, 85, 76, 66, 57, 52,
            179, 175, 167, 159, 150, 141, 133, 125, 116, 108, 100,  91,  82,  72,  63,  58,
            186, 182, 174, 166, 157, 149, 141, 132, 124, 115, 106,  96,  87,  77,  68,  63,
            193, 188, 181, 172, 164, 156, 148, 139, 130, 121, 112, 102,  93,  83,  74,  69,
            200, 195, 188, 179, 171, 162, 154, 145, 136, 126, 117, 107,  98,  88,  79,  74,
            206, 202, 195, 186, 178, 169, 160, 151, 142, 132, 123, 113, 104,  94,  85,  80,
            213, 209, 202, 194, 184, 175, 166, 157, 148, 138, 128, 118, 109,  99,  90,  85,
            220, 216, 209, 200, 191, 181, 172, 163, 153, 144, 134, 124, 115, 105,  96,  91,
            227, 223, 215, 206, 197, 187, 177, 168, 159, 149, 139, 129, 120, 110, 101,  96,
            234, 229, 221, 212, 203, 193, 183, 173, 164, 155, 145, 135, 126, 116, 107, 102,
            241, 236, 227, 218, 209, 199, 189, 179, 169, 160, 151, 141, 131, 121, 112, 107,
            244, 239, 230, 220, 212, 202, 192, 182, 172, 162, 154, 144, 134, 124, 115, 110
          ]
        end

        it "works" do
          c = ZIMG::JPEG::Component.new(0, 0x11, 0)
          c.instance_variable_set("@decoded_lines", encoded_input)
          c.instance_variable_set("@downsampled_width", downsampled_width)
          c.instance_variable_set("@downsampled_height", input.size / downsampled_width)
          expect(c.h2v2_fancy_upsample(16, 16).to_a).to eq(output)
        end
      end
    end

    # from ImageMagick/images/bluebells_clipped.jpg
    describe "192x144 => 384x288" do
      let(:downsampled_width) { 192 }

      describe "Cb" do
        let(:input)  { File.binread(sample("jpeg/bluebells_clipped.cb")).each_byte.to_a }
        let(:output) { File.binread(sample("jpeg/bluebells_clipped.cb.x2")).each_byte.to_a }

        it "works" do
          c = ZIMG::JPEG::Component.new(0, 0x11, 0)
          c.instance_variable_set("@decoded_lines", encoded_input)
          c.instance_variable_set("@downsampled_width", downsampled_width)
          c.instance_variable_set("@downsampled_height", input.size / downsampled_width)
          result = c.h2v2_fancy_upsample(384, 288).to_a
          result.each_slice(upsampled_width).with_index do |slice, idx|
            ref_slice = output[upsampled_width * idx, upsampled_width]
            next unless slice != ref_slice

            td = []
            upsampled_width.times do |i|
              td << ref_slice[i] - slice[i]
            end
            i = 0
            i += 1 while slice[i] == ref_slice[i]
            raise "ref: #{ref_slice}\ngot: #{slice}\ntd:  #{td}\ndiff at row #{idx}, pos #{i}"
            # expect(result).to eq(output[upsampled_width*idx, upsampled_width])
          end
        end
      end
    end
  end # h2v2_fancy_upsample
end # upsample
