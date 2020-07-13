# frozen_string_literal: true

require 'sprockets/digest_utils'
require 'sprockets/source_map_utils' if Gem::Version.new(::Sprockets::VERSION) >= Gem::Version.new('4.x')

class Terser
  class Compressor
    VERSION = '1'

    def initialize(options = {})
      options[:comments] ||= :none
      @options = options
      @cache_key = -"Terser:#{::Terser::VERSION}:#{VERSION}:#{::Sprockets::DigestUtils.digest(options)}"
    end

    def self.instance
      @instance ||= new
    end

    def self.call(input)
      instance.call(input)
    end

    def self.cache_key
      instance.cache_key
    end

    attr_reader :cache_key

    if Gem::Version.new(::Sprockets::VERSION) >= Gem::Version.new('4.x')
      def call(input)
        input_options = { source_map: { filename: input[:filename] } }
        terser = ::Terser.new(@options.merge(input_options))

        js, map = terser.compile_with_map(input[:data])

        map = SourceMapUtils.format_source_map(JSON.parse(map), input)
        map = SourceMapUtils.combine_source_maps(input[:metadata][:map], map)

        { data: js, map: map }
      end
    else
      def call(input)
        terser = ::Terser.new(@options)
        terser.compile(input[:data])
      end
    end
  end
end
