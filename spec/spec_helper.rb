# frozen_string_literal: true

require "zimg"

SAMPLES_DIR = File.join(
  File.dirname(
    File.dirname(
      File.expand_path(__FILE__)
    )
  ),
  "samples"
)

def each_sample(glob)
  Dir[File.join(SAMPLES_DIR, glob)].each do |fname|
    yield fname.sub("#{Dir.pwd}/", "")
  end
end

def sample(fname)
  File.join(SAMPLES_DIR, fname)
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
