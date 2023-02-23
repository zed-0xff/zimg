# frozen_string_literal: true

require "rainbow/ext/string"

class String
  %i[black red green yellow blue magenta cyan white].each do |color|
    next if instance_methods.include?(color)

    define_method color do
      color(color)
    end
    define_method "bright_#{color}" do
      color(color).bright
    end
  end

  %i[gray grey].each do |color|
    next if instance_methods.include?(color)

    define_method color do
      color(:black).bright
    end
  end
end
