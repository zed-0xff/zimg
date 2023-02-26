# coding: binary
# frozen_string_literal: true

NEW_IMG_WIDTH  = 20
NEW_IMG_HEIGHT = 10

RSpec.describe ZIMG::Image do
  shared_examples "exported image" do |bpp = 32|
    let(:eimg) { img.export }
    let(:img2) { described_class.new(eimg) }

    it "has PNG header" do
      expect(eimg).to start_with(ZIMG::PNG::MAGIC)
    end

    describe "parsed again" do
      it "is a ZIMG::Image" do
        expect(img2).to be_instance_of(described_class)
      end

      it "is of specified size" do
        expect(img2.width).to eq NEW_IMG_WIDTH
        expect(img2.height).to eq NEW_IMG_HEIGHT
      end

      it "has bpp = #{bpp}" do
        expect(img2.hdr.bpp).to eq bpp
      end

      it "has 3 chunks: IHDR, IDAT, IEND" do
        expect(img2.chunks.map(&:type)).to eq %w[IHDR IDAT IEND]
      end
    end
  end

  describe ".new" do
    let(:img) { described_class.new width: NEW_IMG_WIDTH, height: NEW_IMG_HEIGHT }

    it "returns ZIMG::Image" do
      expect(img).to be_instance_of(described_class)
    end

    it "creates new image of specified size" do
      expect(img.width).to eq NEW_IMG_WIDTH
      expect(img.height).to eq NEW_IMG_HEIGHT
    end

    include_examples "exported image" do
      it "has all pixels transparent" do
        NEW_IMG_HEIGHT.times do |y|
          NEW_IMG_WIDTH.times do |x|
            expect(img2[x, y]).to be_transparent
          end
        end
      end
    end

    describe "setting imagedata" do
      before do
        imagedata_size = NEW_IMG_WIDTH * NEW_IMG_HEIGHT * 4
        imagedata = "\x00" * imagedata_size
        imagedata_size.times do |i|
          imagedata.setbyte(i, i & 0xff)
        end
        img.imagedata = imagedata
      end

      include_examples "exported image" do
        it "does not have all pixels transparent" do
          skip "TBD"
          NEW_IMG_HEIGHT.times do |y|
            NEW_IMG_WIDTH.times do |x|
              expect(img2[x, y]).not_to be_transparent
            end
          end
        end
      end
    end
  end

  describe ".from_rgb" do
    let(:data) do
      data_size = NEW_IMG_WIDTH * NEW_IMG_HEIGHT * 3
      data = "\x00" * data_size
      data_size.times do |i|
        data.setbyte(i, i & 0xff)
      end
      data
    end

    let(:img) { ZIMG.from_rgb(data, width: NEW_IMG_WIDTH, height: NEW_IMG_HEIGHT) }

    include_examples "exported image", 24 do
      it "has pixels from passed data" do
        i = (0..255).cycle
        NEW_IMG_HEIGHT.times do |y|
          NEW_IMG_WIDTH.times do |x|
            expect(img2[x, y]).to eq ZIMG::Color.new(i.next, i.next, i.next)
          end
        end
      end
    end
  end

  describe ".from_rgba" do
    let(:data) do
      data_size = NEW_IMG_WIDTH * NEW_IMG_HEIGHT * 4
      data = "\x00" * data_size
      data_size.times do |i|
        data.setbyte(i, i & 0xff)
      end
      data
    end

    let(:img) { ZIMG.from_rgba(data, width: NEW_IMG_WIDTH, height: NEW_IMG_HEIGHT) }

    include_examples "exported image" do
      it "has pixels from passed data" do
        i = (0..255).cycle
        NEW_IMG_HEIGHT.times do |y|
          NEW_IMG_WIDTH.times do |x|
            expect(img2[x, y]).to eq ZIMG::Color.new(i.next, i.next, i.next, i.next)
          end
        end
      end
    end
  end
end
