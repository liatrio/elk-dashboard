Gem::Specification.new do |s|
  s.name            = 'logstash-input-jenkins'
  s.version         = '0.1.0'
  s.licenses        = ['Apache-2.0']
  s.summary         = 'Jenkins input plugin'
  s.description     = 'Create an endpoint to recieve data from Jenkins and aggregate analytic data'
  s.authors         = ['Chris Schreiber']
  s.email           = 'chriss@liatrio.com'
  s.require_paths   = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0"
  s.add_runtime_dependency "logstash-mixin-http_client", "~> 6.0"
  s.add_runtime_dependency 'stud', '>= 0.0.22'

  s.add_development_dependency 'logstash-devutils', '~> 1.3'
  s.add_development_dependency 'logstash-codec-json', '~> 3.0'
end
