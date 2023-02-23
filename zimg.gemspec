# frozen_string_literal: true

require_relative "lib/zimg/version"

Gem::Specification.new do |spec|
  spec.name = "zimg"
  spec.version = ZIMG::VERSION
  spec.authors = ["Andrey \"Zed\" Zaikin"]
  spec.email = ["zed.0xff@gmail.com"]

  spec.summary = "pure ruby png/bmp/jpeg/... image files manipulation & validation"
  spec.homepage = "http://github.com/zed-0xff/zimg"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "iostruct", ">= 0.0.5"
  spec.add_dependency "zhexdump"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
