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

terser = Terser.new
uglifier = Uglifier.new
harmony_uglifier = Uglifier.new(harmony: true)
content = File.binread(ARGV[0]) rescue nil
content ||= <<-JS
function Foo(a, b) {
  this.a = a;
  this.b = b;
}
Foo.prototype.show = function () {
  alert(this.a);
};
JS
puts ''
puts "original size: #{content.size}"
puts "terser: #{Terser.compile(content).size}"
puts "uglifier: #{Uglifier.compile(content).size}"
puts "uglifier harmony: #{Uglifier.compile(content, harmony: true).size}"

puts ''
puts 'benchmark'
Benchmark.ips do |x|
  x.report("terser") { Terser.compile(content) }
  x.report("uglifier") { Uglifier.compile(content) }
  x.report("uglifier harmony") { Uglifier.compile(content, harmony: true) }
  x.report("terser precompiled") { terser.compile(content) }
  x.report("uglifier precompiled") { uglifier.compile(content) }
  x.report("uglifier harmony precompiled") { harmony_uglifier.compile(content) }
  x.compare!
end
