# frozen_string_literal: true

RSpec.describe ZIMG::PNG::Metadata do
  # itxt.png contains all possible text chunks
  describe "itxt.png" do
    let!(:metadata) do
      ZIMG.load(File.join(PNG_SAMPLES_DIR, "itxt.png")).metadata
    end

    it "gets all values" do
      expect(metadata.size).to eq 4
    end

    it "does not find not existing value" do
      expect(metadata["foobar"]).to be_nil
    end

    # rubocop:disable Layout/LineLength
    it "finds all existing values" do
      expect(metadata["Title"]).to eq "PNG"
      expect(metadata["Author"]).to eq "La plume de ma tante"
      expect(metadata["Warning"]).to eq "Es is verboten, um diese Datei in das GIF-Bildformat\numzuwandeln.  Sie sind gevarnt worden."
      expect(metadata["Description"]).to match(/Since POV-Ray does not direclty support/)
    end
    # rubocop:enable Layout/LineLength
  end
end
