# frozen_string_literal: true

RSpec.describe ZIMG::Image do
  def _new_img(bpp, color)
    described_class.new(width: 16, height: 1, bpp: bpp, color: color)
  end

  #  before :all do
  #    $html = "<style>img {width:64px}</style>\n<div style='background-color:#ccc'>\n"
  #  end

  [1, 2, 4, 8, 16, 24, 32].each do |bpp|
    [true, false].each do |color|
      next if bpp == 16 && color

      describe "new( :bpp => #{bpp}, :color => #{color} )" do
        16.times do |x|
          it "sets pixel at pos #{x}" do
            bg = ZIMG::Color::BLACK
            fg = ZIMG::Color::WHITE

            img = _new_img bpp, color
            if img.palette
              img.palette << bg if img.palette
            else
              img.width.times { |i| img[i, 0] = bg }
            end
            img[x, 0] = fg

            s = "#" * 16
            s[x] = " "
            expect(img.to_ascii("# ")).to eq s

            #          fname = "out-#{x}-#{bpp}-#{color}.png"
            #          img.save fname
            #          $html << "<img src='#{fname}'><br/>\n"
          end
        end
      end
    end
  end

  #  after :all do
  #    $html << "</div>"
  #    File.open("index.html","w"){ |f| f<<$html }
  #  end
end
