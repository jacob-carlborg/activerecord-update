# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'activerecord-update/version'

Gem::Specification.new do |spec|
  spec.name          = 'activerecord-update'
  spec.version       = ActiveRecord::Update::VERSION
  spec.authors       = ['Jacob Carlborg']
  spec.email         = ['doob@me.se']

  spec.summary       = 'Batch updating for ActiveRecord models'
  spec.description   = 'Batch updating for ActiveRecord models'
  spec.homepage      = 'https://github.com/jacob-carlborg/activerecord-update'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the
  # 'allowed_push_host' to allow pushing to a single host or delete this section
  # to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '4.1.9'
  spec.add_dependency 'activesupport', '4.1.9'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'pg', '0.18.2'
  spec.add_development_dependency 'pry-rescue', '~> 1.4'
  spec.add_development_dependency 'pry-stack_explorer', '~> 0.4.9'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'redcarpet', '~> 3.3'
  spec.add_development_dependency 'rspec', '~> 3.5'
  spec.add_development_dependency 'rubocop', '0.46.0'
  spec.add_development_dependency 'yard', '~> 0.9'
end
