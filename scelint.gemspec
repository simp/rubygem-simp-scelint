require_relative 'lib/scelint/version'

Gem::Specification.new do |spec|
  spec.name          = 'scelint'
  spec.version       = Scelint::VERSION
  spec.authors       = ['Steven Pritchard']
  spec.email         = ['simp@simp-project.org']
  spec.license       = 'Apache-2.0'

  spec.summary       = 'Linter SIMP Compliance Engine data'
  spec.homepage      = 'https://github.com/simp/rubygem-simp-scelint'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.7.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  # spec.metadata['changelog_uri'] = 'TODO: Put your gem's CHANGELOG.md URL here.'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'deep_merge', '~> 1.2'
  spec.add_dependency 'thor', '~> 1.3'
  spec.add_dependency 'compliance_engine', '~> 0.1.0'
end
