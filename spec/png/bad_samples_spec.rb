# frozen_string_literal: true

require "zimg/cli"

each_sample("png/bad/*.png") do |fname|
  RSpec.describe fname do
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      @img = ZIMG.load(fname, verbose: -2)
    end

    it "returns dimensions" do
      expect do
        @img.width
        @img.height
      end.not_to raise_error
    end

    it "accesses 1st pixel" do
      skip "no BPP" unless @img.bpp
      expect(@img[0, 0]).to be_instance_of(ZIMG::Color)
    end

    it "accessess all pixels" do
      skip "no BPP" unless @img.bpp
      skip if File.basename(fname) == "b1.png"
      skip if File.basename(fname) == "000000.png"
      n = 0
      @img.each_pixel do |px|
        expect(px).to be_instance_of(ZIMG::Color)
        n += 1
      end
      expect(n).to eq @img.width * @img.height
    end

    describe "CLI" do
      it "shows info & chunks" do
        expect { ZIMG::CLI.new([fname, "-qqq"]).run }.to output(/#{@img.width}x#{@img.height}/).to_stdout
      end

      it "shows scanlines" do
        skip "no BPP" unless @img.bpp
        expect { ZIMG::CLI.new([fname, "-qqq", "--scanlines"]).run }.to output(/Scanline/).to_stdout
        # TODO: check if all scanlines were actually shown
        # sl = out.scan(/scanline/i)
        # sl.size.should > 0
        # sl.size.should == @img.scanlines.size
      end
    end
  end
end
