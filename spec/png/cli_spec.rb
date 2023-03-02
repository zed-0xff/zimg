# frozen_string_literal: true

require "zimg/cli"

RSpec.describe "CLI" do
  PNGSuite.each_good do |fname|
    describe fname.sub(%r{\A#{Regexp.escape(Dir.getwd)}/?}, "") do
      it "works" do
        expect { ZIMG::CLI.new([fname]).run }.to output(/IEND/).to_stdout
      end

      it "works verbosely" do
        expect { ZIMG::CLI.new([fname, "-vvv"]).run }.to output(/\.\.\.\.IEND/).to_stdout
      end

      it "to ASCII" do
        expect { ZIMG::CLI.new([fname, "-A"]).run }.to output.to_stdout
      end

      it "to ANSI" do
        expect { ZIMG::CLI.new([fname, "-N"]).run }.to output(/\e\[0m/).to_stdout
      end

      it "to ANSI256" do
        expect { ZIMG::CLI.new([fname, "-2"]).run }.to output(/\e\[0m/).to_stdout
      end
    end
  end

  it "cuts long metadata" do
    fname = File.join(PNG_SAMPLES_DIR, "cats.png")
    expect { ZIMG::CLI.new([fname]).run }.to output(/\A.{2500,5000}\Z/m).to_stdout
  end
end
