# frozen_string_literal: true

RSpec.describe ZIMG::Image do
  it "creates image" do
    img = described_class.new width: 16, height: 16
    expect do
      10.times do
        img[rand(16), rand(16)] = ZIMG::Color::BLACK
      end
      img.export
    end.not_to raise_error
  end
end
