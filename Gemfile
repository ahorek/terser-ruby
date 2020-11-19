# frozen_string_literal: true

source "https://rubygems.org"

gemspec

unless RUBY_VERSION < '2.5'
  group :development do
    gem 'rubocop', '~> 1.3.1'
    gem 'rubocop-performance', '~> 1.9.0', :require => false
  end
end
