# -*- encoding: utf-8 -*-

require File.expand_path('../lib/cicd/builder/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'cicd-builder'
  gem.version       = CiCd::Builder::VERSION
  gem.summary       = 'Jenkins builder task for CI/CD'
  gem.description   = 'Jenkins builder task for Continuous Integration/Continuous Delivery artifact promotion style deployments'
  gem.license       = 'Apachev2'
  gem.authors       = ['Christo De Lange']
  gem.email         = 'rubygems@dldinternet.com'
  gem.homepage      = 'https://rubygems.org/gems/cicd-builder'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'awesome_print', '>= 1.6', '< 2.0'
  gem.add_dependency 'inifile', '>= 3.0.0', '< 3.1'
  gem.add_dependency 'logging', '>= 1.8.2', '< 1.9'
  gem.add_dependency 'json', '>= 1.8.1', '< 1.9'
  gem.add_dependency 'chef', '>= 12.0.3', '< 12.1'
  gem.add_dependency 'aws-sdk', '>= 2.0', '< 2.1'
  gem.add_dependency 'yajl-ruby', '>= 1.2.1', '< 1.3'
  gem.add_dependency 'git', '>= 1.2.7', '< 1.3'
  gem.add_dependency 'semverse', '>= 1.2.1', '< 1.3'
  gem.add_dependency 'artifactory', '>= 2.2.1', '< 2.3'

  gem.add_development_dependency 'bundler', '>= 1.7', '< 1.8'
  gem.add_development_dependency 'rake', '>= 10.3', '< 11'
  gem.add_development_dependency 'rubygems-tasks', '>= 0.2', '< 1.1'
  gem.add_development_dependency 'cucumber', '>= 0.10.7', '< 0.11'
end
