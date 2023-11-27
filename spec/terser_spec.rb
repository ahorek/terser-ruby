# encoding: UTF-8
# frozen_string_literal: true

require 'stringio'
require File.expand_path("#{File.dirname(__FILE__)}/spec_helper")

describe "Terser" do
  it "minifies JS" do
    source = File.open("lib/terser.js", "r:UTF-8", &:read)
    minified = Terser.new.compile(source)
    expect(minified.length).to be < source.length
    expect { ExecJS.compile(minified) }.not_to raise_error
  end

  it "minifies JS with ECMA6 features" do
    source = "const foo = () => bar();"
    minified = Terser.new(:compress => false).compile(source)
    expect(minified.length).to be < source.length
  end

  it "doesn't crash on eval undefined" do
    source = "() => { let x; console.log(x + `?ts=${Date.now()}`); };"
    minified = Terser.new(:compress => { :evaluate => true, :reduce_vars => true, :side_effects => false }).compile(source)
    expect(minified).to include('undefined')
  end

  it "includes an error message" do
    begin
      Terser.new(:compress => true).compile(")(")
    rescue Terser::Error => e
      expect(e.message).to include("Unexpected token")
    else
      raise "Terser::Error expected"
    end
  end

  it "throws an exception when compilation fails" do
    expect { Terser.new.compile(")(") }.to raise_error(Terser::Error)
  end

  it "throws an exception on invalid option" do
    expect { Terser.new(:foo => true) }.to raise_error(ArgumentError)
  end

  it "doesn't omit null character in strings" do
    expect(Terser.new.compile('var foo="\0bar"')).to include("\\0bar")
  end

  describe "property name mangling" do
    let(:source) do
      <<-JS
       var obj = {
          _hidden: false,
          "quoted": 'value'
        };

        alert(object.quoted);
      JS
    end

    it "does not mangle property names by default" do
      expect(Terser.compile(source)).to include("object.quoted")
    end

    it "can be configured to mangle properties" do
      expect(Terser.compile(source, :mangle => { :properties => true }))
        .not_to include("object.quoted")
    end

    it "can be configured using old mangle_properties" do
      expect(Terser.compile(source, :mangle_properties => true))
        .not_to include("object.quoted")
    end

    it "can configure a regex for mangling" do
      expect(Terser.compile(source, :mangle => { :properties => { :regex => /^_/ } }))
        .to include("object.quoted")
    end

    it "can be configured to keep quoted properties" do
      expect(Terser.compile(source, :mangle => { :properties => { :keep_quoted => true } }))
        .to include("object.quoted")
    end

    it "can be configured to include debug in mangled properties" do
      expect(Terser.compile(source, :mangle => { :properties => { :debug => true } }))
        .to include("_$quoted$_")
    end
  end

  describe "argument name mangling" do
    let(:code) { "function bar(foo) {return foo + 'bar'};" }

    it "doesn't try to mangle $super by default to avoid breaking PrototypeJS" do
      expect(Terser.compile('function foo($super) {return $super}')).to include("$super")
    end

    it "allows variables to be excluded from mangling" do
      expect(Terser.compile(code, :mangle => { :reserved => ["foo"] }))
        .to include("(foo)")
    end

    it "skips mangling when set to false" do
      expect(Terser.compile(code, :mangle => false)).to include("(foo)")
    end

    it "mangles argument names by default" do
      expect(Terser.compile(code)).not_to include("(foo)")
    end

    it "mangles top-level names when explicitly instructed" do
      expect(Terser.compile(code, :mangle => { :toplevel => false }))
        .to include("bar(")
      expect(Terser.compile(code, :mangle => { :toplevel => true }))
        .not_to include("bar(")
    end

    it "can be controlled with mangle option" do
      expect(Terser.compile(code, :mangle => false)).to include("(foo)")
    end
  end

  describe "comment preservation" do
    let(:source) do
      <<-JS
        /* @preserve Copyright Notice */
        /* (c) 2011 */
        // INCLUDED
        //! BANG
        function identity(p) { return p; }
        /* Another Copyright */
        /*! Another Bang */
        // A comment!
        function add(a, b) { return a + b; }
      JS
    end

    describe ":copyright" do
      subject { Terser.compile(source, :comments => :copyright) }

      it "preserves comments with string Copyright" do
        expect(subject).to match(/Copyright Notice/)
        expect(subject).to match(/Another Copyright/)
      end

      it "preserves comments that start with a bang (!)" do
        expect(subject).to match(/! BANG/)
        expect(subject).to match(/! Another Bang/)
      end

      it "ignores other comments" do
        expect(subject).not_to match(/INCLUDED/)
        expect(subject).not_to match(/A comment!/)
      end
    end

    describe ":jsdoc" do
      subject { Terser.compile(source, :output => { :comments => :jsdoc }) }

      it "preserves jsdoc license/preserve blocks" do
        expect(subject).to match(/Copyright Notice/)
      end

      it "ignores other comments" do
        expect(subject).not_to match(/Another Copyright/)
      end
    end

    describe ":all" do
      subject { Terser.compile(source, :comments => :all) }

      it "preserves all comments" do
        expect(subject).to match(/INCLUDED/)
        expect(subject).to match(/2011/)
      end
    end

    describe ":none" do
      subject { Terser.compile(source, :comments => :none) }

      it "omits all comments" do
        expect(subject).not_to match(%r{//})
        expect(subject).not_to match(%r{/\*})
      end
    end

    describe "regular expression" do
      subject { Terser.compile(source, :comments => /included/i) }

      it "matches comment blocks with regex" do
        expect(subject).to match(/INCLUDED/)
      end

      it "omits other blocks" do
        expect(subject).not_to match(/2011/)
      end
    end
  end

  it "honors max line length" do
    code = "var foo = 123;function bar() { return foo; }"
    terser = Terser.new(:output => { :max_line_len => 20 }, :compress => false)
    expect(terser.compile(code).split("\n").map(&:length)).to all(be < 28)
  end

  it "hoists vars to top of the scope" do
    code = <<-JS
      function f() {
        var a = 1;
        var b = 2;
        var c = 3;
        function g() {}
        return g(a, b, c);
      }
    JS
    minified = Terser.compile(code, :compress => { :hoist_vars => true })
    expect(minified).to match(/var \w=\d+,\w=\d+/)
  end

  describe 'reduce_funcs' do
    let(:code) do
      <<-JS
        var foo = function(x, y, z) {
          return x < y ? x * y + z : x * z - y;
        }
        var indirect = function(x, y, z) {
          return foo(x, y, z);
        }
        var sum = 0;
        for (var i = 0; i < 100; ++i)
          sum += indirect(i, i + 1, 3 * i);
        console.log(sum);
      JS
    end

    it 'inlines function declaration' do
      minified = Terser.compile(
        code,
        :mangle => false,
        :compress => {
          :inline => true,
          :reduce_vars => true,
          :toplevel => true,
          :unused => true
        }
      )
      expect(minified).not_to include("indirect(")
      expect(minified).not_to include("foo(")
    end

    it 'not inlining function declarations' do
      minified = Terser.compile(
        code,
        :mangle => false,
        :compress => {
          :inline => false,
          :reduce_vars => true,
          :toplevel => true,
          :unused => true
        }
      )

      expect(minified).to include("indirect(")
      expect(minified).not_to include("foo(")
    end

    it 'preserves top level function declarations' do
      minified = Terser.compile(
        code,
        :mangle => false,
        :compress => {
          :inline => false,
          :reduce_vars => true,
          :toplevel => false,
          :unused => true
        }
      )

      expect(minified).to include("indirect(")
      expect(minified).to include("foo(")
    end
  end

  describe 'reduce_vars' do
    let(:code) do
      <<-JS
        var a = 2;
        (function () {
          console.log(a - 5);
          console.log(a - 1);
        })();
      JS
    end

    it "reduces vars when compress option is set" do
      minified = Terser.compile(code, :compress => { :reduce_vars => true, :toplevel => true })
      expect(minified).to include("console.log(-3)")
    end

    it "does not reduce vars when compress option is false" do
      minified = Terser.compile(code, :compress => { :reduce_vars => false, :toplevel => true })
      expect(minified).to match(/console.log\(\w+-5\)/)
    end

    it "defaults to variable reducing being disabled" do
      expect(Terser.compile(code))
        .to eq(Terser.compile(code, :compress => { :reduce_vars => false, :toplevel => true }))
    end

    it "does not reduce variables that are assigned to" do
      options = { :mangle => false, :compress => { :reduce_vars => true } }
      expect(Terser.compile("#{code}a=3", options)).to match(/console.log\(\w+-5\)/)
    end
  end

  it "can be configured to output only ASCII" do
    code = "function emoji() { return '\\ud83c\\ude01'; }"
    minified = Terser.compile(code, :output => { :ascii_only => true })
    expect(minified).to include("\\ud83c\\ude01")
  end

  it "escapes </script when asked to" do
    code = "function test() { return '</script>';}"
    minified = Terser.compile(code, :output => { :inline_script => true })
    expect(minified).not_to include("</script>")
  end

  it "quotes keys" do
    code = "var a = {foo: 1}"
    minified = Terser.compile(code, :output => { :quote_keys => true })
    expect(minified).to include('"foo"')
  end

  it "quotes unicode keys by default" do
    code = 'var code = {"\u200c":"A"}'

    expect(Terser.compile(code)).to include('"\u200c"')

    terser = Terser.new(:output => { :ascii_only => false, :quote_keys => false })
    expect(terser.compile(code)).to include(["200c".to_i(16)].pack("U*"))
  end

  it "handles constant definitions" do
    code = "if (BOOL) { var a = STR; var b = NULL; var c = NUM; }"
    defines = { "NUM" => 1234, "BOOL" => true, "NULL" => nil, "STR" => "str" }
    processed = Terser.compile(code, :define => defines)
    expect(processed).to include("a=\"str\"")
    expect(processed).not_to include("if")
    expect(processed).to include("b=null")
    expect(processed).to include("c=1234")
  end

  it "can disable IIFE negation" do
    code = "(function(value) { console.log(value)})(value);"
    disabled_negation = Terser.compile(code, :compress => { :negate_iife => false })
    expect(disabled_negation).not_to include("!")
    negation = Terser.compile(code, :compress => { :negate_iife => true })
    expect(negation).to include("!")
  end

  it "can drop console logging" do
    code = "(function() { console.log('test')})();"
    compiled = Terser.compile(code, :compress => { :drop_console => true })
    expect(compiled).not_to include("console")
  end

  describe "collapse_vars option" do
    let(:code) do
      <<-JS
        function a() {
          var win = window;
          return win.Handlebars;
        }
      JS
    end

    it "collapses vars when collapse_vars is enabled" do
      compiled = Terser.compile(code, :compress => { :collapse_vars => true })
      expect(compiled).to include("return window.Handlebars")
    end

    it "does not collapse variables when disable" do
      compiled = Terser.compile(code, :compress => { :collapse_vars => false })
      expect(compiled).not_to include("return window.Handlebars")
    end

    it "defaults to not collapsing variables" do
      expect(Terser.compile(code)).to include("return window.Handlebars")
    end

    it "collapse self-assignment" do
      code = 'export function f(x) { x = x; }'
      expect(Terser.compile(code, :compress => { :collapse_vars => true })).to include("export function f(){}")
    end
  end

  it "keeps unused function arguments when keep_fargs option is set" do
    code = <<-JS
    function plus(a, b, c) { return a + b};
    plus(1, 2);
    JS

    options = lambda do |keep_fargs|
      {
        :mangle => false,
        :compress => {
          :keep_fargs => keep_fargs,
          :unsafe => true
        }
      }
    end

    expect(Terser.compile(code, options.call(false))).not_to include("c)")
    expect(Terser.compile(code, options.call(true))).to include("c)")
  end

  describe 'keep_fnames' do
    let(:code) do
      <<-JS
      (function() {
        function plus(a, b) { return a + b; };
        plus(1, 2);
      })();
      JS
    end

    it "keeps function names in output when compressor keep_fnames is set" do
      expect(Terser.compile(code, :compress => true)).not_to include("plus")

      keep_fnames = Terser.compile(code, :mangle => false, :compress => { :keep_fnames => true })
      expect(keep_fnames).to include("plus")
    end

    it "does not mangle function names in output when mangler keep_fnames is set" do
      expect(Terser.compile(code, :mangle => true)).not_to include("plus")

      keep_fnames = Terser.compile(code, :mangle => { :keep_fnames => true })
      expect(keep_fnames).to include("plus")
    end

    it "sets sets both compress and mangle keep_fnames when toplevel keep_fnames is true" do
      expect(Terser.compile(code)).not_to include("plus")

      keep_fnames = Terser.compile(code, :keep_fnames => true)
      expect(keep_fnames).to include("plus")
    end
  end

  describe 'keep_classnames' do
    let(:code) do
      <<-JS
      function foo() {
        class Bar {}
      }
      JS
    end

    it "keeps function names in output when compressor keep_classnames is set" do
      out = Terser.compile(code, :compress => false, :keep_classnames => true)
      expect(out).to include("Bar")
    end

    it "keeps function names in output when compressor keep_classnames is set as regex" do
      out = Terser.compile(code, :compress => false, :keep_classnames => /Bar$/)
      expect(out).to include("Bar")
    end

    it "keeps function names in output when compressor keep_classnames is set via mangle" do
      out = Terser.compile(code, :compress => false, :mangle => { :keep_classnames => true })
      expect(out).to include("Bar")
    end

    it "keeps function names in output when compressor keep_classnames is false" do
      out = Terser.compile(code, :compress => false, :keep_classnames => false)
      expect(out).not_to include("Bar")
    end

    it "keeps function names in output when compressor keep_classnames is not set" do
      out = Terser.compile(code, :compress => false)
      expect(out).not_to include("Bar")
    end
  end

  describe 'keep_numbers' do
    let(:code) do
      <<-JS
      function foo() {
        return 1000000000000;
      }
      JS
    end

    it "keeps number in the original form" do
      out = Terser.compile(code, :compress => false, :output => { :keep_numbers => true })
      expect(out).to include("1000000000000")
    end

    it "uses a short form" do
      out = Terser.compile(code, :compress => false, :output => { :keep_numbers => false })
      expect(out).to include("1e12")
    end
  end

  describe "Input Formats" do
    let(:code) { "function hello() { return 'hello world'; }" }

    it "handles strings" do
      expect(Terser.new.compile(code)).not_to be_empty
    end

    it "handles IO objects" do
      expect(Terser.new.compile(StringIO.new(code))).not_to be_empty
    end
  end

  describe "wrap_iife option" do
    let(:code) do
      <<-JS
        (function(value) {
          return function() {
            console.log(value)
          };
        })(1)();
      JS
    end

    it "defaults to not wrap IIFEs" do
      expect(Terser.compile(code))
        .to match("!function(n){return function(){console.log(n)}}(1)();")
    end

    it "wraps IIFEs" do
      expect(Terser.compile(code, :output => { :wrap_iife => true }))
        .to match("(function(n){return function(){console.log(n)}})(1)();")
    end
  end

  describe 'removing unused top-level functions and variables' do
    let(:code) do
      <<-JS
        var a, b = 1, c = g;
        function f(d) {
          return function() {
            c = 2;
          }
        }
        a = 2;
        function g() {}
        function h() {}
        console.log(b = 3);
      JS
    end

    it 'removes unused top-level functions and variables when toplevel is set' do
      compiled = Terser.compile(
        code,
        :mangle => false,
        :compress => { :toplevel => true }
      )
      expect(compiled).not_to include("function h()")
      expect(compiled).not_to include("var a")
    end

    it 'does not unused top-level functions and variables by default' do
      expect(Terser.compile(code, :mangle => false))
        .to include("var a").and(include("function h()"))
    end

    it 'keeps variables specified in top_retain' do
      compiled = Terser.compile(
        code,
        :mangle => false,
        :compress => { :toplevel => true, :top_retain => %w(a h) }
      )
      expect(compiled).to include("var a").and(include("function h()"))
      expect(compiled).not_to include("function g")
    end
  end

  describe 'unsafe_comps' do
    let(:code) do
      <<-JS
        var obj1, obj2;
        obj1 <= obj2 ? f1() : g1();
      JS
    end

    let(:options) do
      {
        :comparisons => true,
        :conditionals => true,
        :reduce_vars => false,
        :collapse_vars => false
      }
    end

    it 'keeps unsafe comparisons by default' do
      compiled = Terser.compile(code, :mangle => false, :compress => options)
      expect(compiled).to include("obj1<=obj2")
    end

    it 'does not loose equality with BigInt == number' do
      code = 'if (-1 !== -1n) console.log("PASS");'
      compiled = Terser.compile(code, :mangle => false, :compress => options)
      expect(compiled).to include('-1!==-1n&&console.log("PASS");')
    end

    it 'optimises unsafe comparisons when unsafe_comps is enabled' do
      compiled = Terser.compile(
        code,
        :mangle => false,
        :compress => options.merge(:unsafe_comps => true)
      )
      expect(compiled).to match(/obj2<obj1|obj1>obj2/)
    end
  end

  describe 'unsafe_math' do
    let(:code) do
      <<-JS
        function compute(x) { return 2 * x * 3; }
      JS
    end

    it 'keeps unsafe math by default' do
      compiled = Terser.compile(code, :mangle => false)
      expect(compiled).to include('2*x*3')
    end

    it 'optimises unsafe math when unsafe_math is enabled' do
      compiled = Terser.compile(
        code,
        :mangle => false,
        :compress => { :unsafe_math => true }
      )
      expect(compiled).to include("6*x")
    end
  end

  describe 'unsafe_proto' do
    let(:code) do
      <<-JS
        Array.prototype.slice.call([1,2,3], 1)
      JS
    end

    it 'keeps unsafe prototype references by default' do
      compiled = Terser.compile(code)
      expect(compiled).to include("Array.prototype.slice.call")
    end

    it 'optimises unsafe comparisons when unsafe_comps is enabled' do
      compiled = Terser.compile(code, :compress => { :unsafe_proto => true })
      expect(compiled).to include("[].slice.call")
    end
  end

  it 'forwards passes option to compressor' do
    code = File.open("lib/terser.js", "r:UTF-8", &:read)
    one_pass = Terser.compile(code, :mangle => false, :compress => { :passes => 1 })
    two_pass = Terser.compile(code, :mangle => false, :compress => { :passes => 2 })
    expect(two_pass.length).to be < one_pass.length
  end

  describe 'shebang' do
    let(:shebang) { '#!/usr/bin/env node' }
    let(:code) { "#{shebang}\nconsole.log('Hello world!')" }

    it 'is not removed by default' do
      compiled = Terser.compile(code)
      expect(compiled).to include("#!")
    end

    it 'is removed when shebang option is set to false' do
      compiled = Terser.compile(code, :output => { :shebang => false })
      expect(compiled).not_to include("#!")
    end
  end

  describe 'keep_infinity' do
    let(:code) do
      <<-JS
        function fun() { return (123456789 / 0).toString(); }
      JS
    end

    it 'compresses Infinity by default' do
      compiled = Terser.compile(code, :compress => {
                                  :evaluate => true,
                                  :keep_infinity => false
                                })
      expect(compiled).not_to include("Infinity")
    end

    it 'can be enabled to preserve Infinity' do
      compiled = Terser.compile(code, :compress => {
                                  :evaluate => true,
                                  :keep_infinity => true
                                })
      expect(compiled).to include("Infinity")
    end
  end

  describe 'lhs_constants' do
    let(:code) do
      <<-JS
        function fun(a) {
          var x;
          x = a == 42;
          x = a === 42;
          return x;
        }
      JS
    end

    it 'compresses with lhs_constants' do
      compiled = Terser.compile(code, :compress => {
                                  :evaluate => true,
                                  :lhs_constants => true
                                })
      expect(compiled).to include("42==n")
      expect(compiled).to include("42===n")
    end

    it 'can be disabled to preserve the order' do
      compiled = Terser.compile(code, :compress => {
                                  :evaluate => true,
                                  :lhs_constants => false
                                })
      expect(compiled).to include("n==42")
      expect(compiled).to include("n===42")
    end
  end

  describe 'quote style' do
    let(:code) do
      <<-JS
        function fun() { return "foo \\"bar\\""; }
      JS
    end

    it 'defaults to auto' do
      compiled = Terser.compile(code)
      expect(compiled).to include("'foo \"bar\"'")
    end

    it 'can use numbers for configuration' do
      compiled = Terser.compile(code, :output => { :quote_style => 2 })
      expect(compiled).to include("\"foo \\\"bar\\\"\"")
    end

    it 'uses single quotes when single' do
      compiled = Terser.compile(code, :output => { :quote_style => :single })
      expect(compiled).to include("'foo \"bar\"'")
    end

    it 'uses double quotes when single' do
      compiled = Terser.compile(code, :output => { :quote_style => :double })
      expect(compiled).to include("\"foo \\\"bar\\\"\"")
    end

    it 'preserves original quoting when original' do
      compiled = Terser.compile(code, :output => { :quote_style => :original })
      expect(compiled).to include("\"foo \\\"bar\\\"\"")
    end
  end

  describe 'keep quoted props' do
    let(:code) do
      <<-JS
        function fun() { return {"foo": "bar"}; }
      JS
    end

    it 'defaults to not keeping quotes' do
      compiled = Terser.compile(code)
      expect(compiled).not_to include('"foo"')
    end

    it 'keeps properties when set to true' do
      compiled = Terser.compile(code, :output => { :keep_quoted_props => true })
      expect(compiled).to include('"foo"')
    end
  end

  describe 'side_effects' do
    let(:code) do
      <<-JS
        function fun() { /*@__PURE__*/foo(); }
      JS
    end

    it 'defaults to dropping pure function calls' do
      compiled = Terser.compile(code)
      expect(compiled).not_to include('foo()')
    end

    it 'function call dropping can be disabled' do
      compiled = Terser.compile(code, :compress => { :side_effects => false })
      expect(compiled).to include('foo()')
    end
  end

  describe 'switches' do
    let(:code) do
      <<-JS
        function fun() {
          switch (1) {
            case 1: foo();
            case 1+1:
              bar();
              break;
            case 1+1+1: baz();
          }
        }
      JS
    end

    it 'drops unreachable switch branches by default' do
      compiled = Terser.compile(code)
      expect(compiled).not_to include('baz()')
    end

    it 'branch dropping can be disabled' do
      compiled = Terser.compile(code, :compress => { :switches => false })
      expect(compiled).to include('baz()')
    end
  end

  describe 'context_source_lines' do
    let(:code) do
      <<-JS
        var foo = { //_1
          // `foo.bar` should cause panic because with `harmony: false`
          bar() { //_3
            console.log('correct es5 syntax:',
              js` //_5
              var foo = {
                bar: function() { //_7
                  console.log('this is correct es5 syntax')
                } //_9
              }
              ` //_11
            );
          }, //_13

          // `foo.baz` ends with `;` which is a syntax error
          baz: () => { //_16
            console.log('foo.baz is incorrect');
          }; //_18
          //extra line
        } //_20
        // end
      JS
    end
  end
end
