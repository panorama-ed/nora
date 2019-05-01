# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "nora/version"

Gem::Specification.new do |spec|
  spec.name          = "nora"
  spec.version       = Nora::VERSION
  spec.authors       = ["Jacob Evelyn"]
  spec.email         = ["jevelyn@panoramaed.com"]

  spec.summary       = "Bringing P-A-NORA-M-A together."
  spec.description   = "Automatically schedule coffee dates with coworkers."
  spec.homepage      = "https://github.com/panorama-ed/nora"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "overcommit", "~> 0.38"
  spec.add_development_dependency "rubocop", "~> 0.49"

  spec.add_dependency "activesupport", "~> 5.0"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "google-api-client", "~> 0.10"
  spec.add_dependency "pony", "~> 1.12"
end
