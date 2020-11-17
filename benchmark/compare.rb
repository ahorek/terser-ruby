# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "terser", git: "https://github.com/ahorek/terser-ruby.git"
  gem "uglifier"
end

require 'terser'
require 'uglifier'
require 'benchmark'

N = 10
es6 = true
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
puts "original size:    #{content.size}"
puts "terser:           #{Terser.compile(content).size}"
begin
  puts "uglifier:         #{Uglifier.compile(content).size}"
rescue Uglifier::Error
  puts 'uglifier: skipped'
  es6 = false
end
puts "uglifier harmony: #{Uglifier.compile(content, harmony: true).size}"

puts ''
puts 'benchmark'
Benchmark.bm do |x|
  x.report("terser                      ") { N.times { Terser.compile(content) } }
  x.report("uglifier                    ") { N.times { Uglifier.compile(content) } } if es6
  x.report("uglifier harmony            ") { N.times { Uglifier.compile(content, harmony: true) } }
  x.report("terser precompiled          ") { N.times { terser.compile(content) } }
  x.report("uglifier precompiled        ") { N.times { uglifier.compile(content) } } if es6
  x.report("uglifier harmony precompiled") { N.times { harmony_uglifier.compile(content) } }
end
