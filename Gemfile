source 'https://rubygems.org'

# Specify your gem's dependencies in scelint.gemspec
gemspec

gem 'rake', '~> 13.2'
gem 'compliance_engine', git: 'https://github.com/simp/rubygem-simp-compliance_engine.git'

group :tests do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.65'
  gem 'rubocop-performance', '~> 1.21'
  gem 'rubocop-rspec', '~> 3.0'
  gem 'rubocop-rake', '~> 0.6.0'
end

group :development do
  gem 'pry', '~> 0.14.1'
  gem 'pry-byebug', '~> 3.10'
  gem 'rdoc', '~> 6.4'
end
