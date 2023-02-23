# frozen_string_literal: true

require "zimg/cli"

each_sample("jpeg/**/*.jpg") do |fname|
  bname = File.basename(fname)
  RSpec.describe bname do
    it "is readable by CLI" do
      expect { ZIMG::CLI.new([fname]).run }.to output(/ECS/).to_stdout
    end

    it "is readable by CLI verbosely" do
      skip("SLOW") if bname == "black-6000x6000.jpg" && !ENV["SLOW"]
      expect { ZIMG::CLI.new([fname, "-vvv"]).run }.to output(/ECS/).to_stdout
    end
  end
end
