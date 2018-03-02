lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'trailblazer/macro/version'

Gem::Specification.new do |spec|
  spec.name          = "trailblazer-macro"
  spec.version       = Trailblazer::Macro::VERSION
  spec.authors       = ["Nick Sutterer"]
  spec.email         = ["apotonick@gmail.com"]
  spec.description   = 'Trailblazer Operation Macros'
  spec.summary       = 'A Macro collection for Trailblazer Operation'
  spec.homepage      = "http://trailblazer.to"
  spec.license       = "LGPL-3.0"

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "trailblazer", ">= 2.1.0.beta4", "< 2.2.0"
  spec.add_development_dependency "trailblazer-activity",  ">= 0.5.0", "< 0.6.0"
  spec.add_development_dependency "trailblazer-operation", ">= 0.2.3", "< 0.3.0"
  spec.add_development_dependency "trailblazer-macro-contract", ">= 2.1.0.beta4", "< 2.2.0"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "nokogiri"
  spec.add_development_dependency "rake"

  spec.required_ruby_version = '>= 2.0.0'
end
