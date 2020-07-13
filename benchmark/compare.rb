# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "terser", git: "https://github.com/ahorek/terser-ruby.git"
  gem "uglifier"
  gem "benchmark-ips"
end

require 'terser'
require 'uglifier'

content = File.binread(ARGV[0])
puts 'size:'
puts "terser: #{Terser.compile(content).size}"
puts "uglifier: #{Uglifier.compile(content).size}"
puts "uglifier harmony: #{Uglifier.compile(content, harmony: true).size}"

puts ''
puts 'benchmark'
Benchmark.ips do |x|
  x.report("terser") { Terser.compile(content) }
  x.report("uglifier") { Uglifier.compile(content) }
  x.report("uglifier harmony") { Uglifier.compile(content, harmony: true) }
  x.compare!
end
