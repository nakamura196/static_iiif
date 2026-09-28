# frozen_string_literal: true

require "rake"
require "rake/tasklib"
require_relative "../static_iiif"

module StaticIIIF
  # Rake task that runs Level0 over a folder of images.
  #
  #   # Rakefile or rakelib/*.rake
  #   require "static_iiif/rake_task"
  #   StaticIIIF::RakeTask.new                      # defines `rake generate_iiif`
  #
  #   rake generate_iiif
  #   rake "generate_iiif[objects,objects/iiif/3,256;1024,4000,512,false]"
  #
  # Arguments (all optional): input_dir, output_dir, sizes (separated by ";"),
  # tile_threshold (0 = never tile), tile_size, force ("true" redoes up-to-date images).
  class RakeTask < ::Rake::TaskLib
    attr_accessor :name, :input_dir, :output_dir, :sizes, :tile_threshold, :tile_size

    def initialize(name = :generate_iiif)
      super()
      @name = name
      @input_dir = "objects"
      @output_dir = "objects/iiif/3"
      @sizes = Level0::DEFAULTS[:sizes]
      @tile_threshold = Level0::DEFAULTS[:tile_threshold]
      @tile_size = Level0::DEFAULTS[:tile_size]
      yield self if block_given?
      define
    end

    private

    def define
      desc "Generate static IIIF Image API level 0 files (sizes; tiles for large images)"
      task name, %i[input_dir output_dir sizes tile_threshold tile_size force] do |_t, args|
        level0 = Level0.new(
          sizes: args[:sizes] ? args[:sizes].split(/[;,\s]+/) : sizes,
          tile_threshold: args[:tile_threshold] || tile_threshold,
          tile_size: args[:tile_size] || tile_size
        )
        abort "#{name}: libvips is required (e.g. `brew install vips` or `apt-get install libvips-tools`)." unless Vips.available?

        input = args[:input_dir] || input_dir
        output = args[:output_dir] || output_dir
        level0.generate_dir(input, output, force: args[:force] == "true") do |src, dir, meta|
          next puts("Skipping: #{dir} is up to date") unless meta

          tiles = meta["tiles"] ? ", tiles" : ""
          puts "Created: #{dir} (#{meta['width']}x#{meta['height']}, #{meta['sizes'].size} sizes#{tiles}) from #{src}"
        end
      end
    end
  end
end
