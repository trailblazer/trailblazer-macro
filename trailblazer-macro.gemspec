lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'trailblazer/macro/version'

Gem::Specification.new do |spec|
  spec.name          = "trailblazer-macro"
  spec.version       = Trailblazer::Version::Macro::VERSION
  spec.authors       = ["Nick Sutterer"]
  spec.email         = ["apotonick@gmail.com"]
  spec.description   = "Macros for Trailblazer's operation"
  spec.summary       = "Macros for Trailblazer's operation: Policy, Wrap, Rescue and more."
  spec.homepage      = "https://trailblazer.to/2.1/docs/activity.html#activity-macro-api"
  spec.license       = "LGPL-3.0"

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"

  spec.add_development_dependency "multi_json"
  spec.add_development_dependency "roar"
  spec.add_development_dependency "trailblazer-developer"

  spec.add_dependency "trailblazer-activity-dsl-linear", ">= 0.5.0", "< 0.6.0"
  spec.add_dependency "trailblazer-operation", ">= 0.7.0" # TODO: this dependency will be removed.

  spec.required_ruby_version = ">=2.6.0"
end
