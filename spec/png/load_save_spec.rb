# frozen_string_literal: true

each_sample("png/*.png") do |fname|
  RSpec.describe fname do
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      @src = ZIMG.load(fname)
      @dst = ZIMG::Image.new(@src.export)
    end

    it "has equal width" do
      expect(@src.width).to eq @dst.width
    end

    it "has equal height" do
      expect(@src.height).to eq @dst.height
    end

    it "has equal data" do
      expect(@src).to eq @dst
    end
  end
end
