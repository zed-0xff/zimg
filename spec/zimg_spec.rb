# frozen_string_literal: true

RSpec.describe ZIMG do
  it "has a version number" do
    expect(ZIMG::VERSION).not_to be_nil
  end

  it "supports JPEG" do
    expect(described_class.supported_formats).to include(:jpeg)
  end
end
