# frozen_string_literal: true

source "https://rubygems.org"

gemspec

unless RUBY_VERSION < '2.6'
  group :development do
    gem 'rubocop', '~> 1.46.0'
    gem 'rubocop-performance', '~> 1.16.0', :require => false
  end
end
