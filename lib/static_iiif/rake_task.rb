# frozen_string_literal: true

require "csv"
require "rake"
require "rake/tasklib"
require "yaml"
require_relative "../static_iiif"

module StaticIIIF
  # Rake task that runs Level0 over a folder of images.
  #
  #   # Rakefile or rakelib/*.rake
  #   require "static_iiif/rake_task"
  #   StaticIIIF::RakeTask.new                      # defines `rake generate_iiif`
  #
  #   rake generate_iiif
  #   rake "generate_iiif[objects,objects/iiif/3,256;1024,4000,512,false,objects/iiif/2]"
  #
  # Arguments (all optional): input_dir, output_dir, sizes (separated by ";"),
  # tile_threshold (0 = never tile), tile_size, force ("true" redoes up-to-date images),
  # v2_output_dir (also make Image API 2 folders there; see Level0.derive_v2).
  #
  # When `_config.yml` gives `metadata:` and `_data/<metadata>.csv` exists (as in
  # CollectionBuilder-CSV), only the images listed in that CSV's `object_location`
  # column are processed, so template demo images left in `objects/` are skipped.
  #
  #   StaticIIIF::RakeTask.new { |t| t.v2_output_dir = "objects/iiif/2" } # version 2 as well
  class RakeTask < ::Rake::TaskLib
    attr_accessor :name, :input_dir, :output_dir, :sizes, :tile_threshold, :tile_size, :v2_output_dir, :only

    def initialize(name = :generate_iiif)
      super()
      @name = name
      @input_dir = "objects"
      @output_dir = "objects/iiif/3"
      @sizes = Level0::DEFAULTS[:sizes]
      @tile_threshold = Level0::DEFAULTS[:tile_threshold]
      @tile_size = Level0::DEFAULTS[:tile_size]
      @v2_output_dir = nil
      @only = nil
      yield self if block_given?
      define
    end

    def self.metadata_images(config_file = "_config.yml", data_dir = "_data")
      return nil unless File.file?(config_file)

      config = YAML.safe_load_file(config_file, permitted_classes: [Date, Time])
      metadata = config.is_a?(Hash) && config["metadata"].to_s.strip
      return nil if metadata.nil? || metadata.empty?

      csv_path = File.join(data_dir, "#{metadata.sub(/\.csv\z/i, '')}.csv")
      return nil unless File.file?(csv_path)

      col = (config.dig("static_iiif", "manifests", "image_column") || "object_location").to_s
      files = []
      CSV.foreach(csv_path, headers: true, encoding: "UTF-8") do |row|
        val = row[col].to_s.strip
        files << val unless val.empty? || val.match?(DataManifests::ABSOLUTE)
      end
      files
    rescue StandardError
      nil
    end

    private

    def define
      desc "Generate static IIIF Image API level 0 files (sizes; tiles for large images)"
      task name, %i[input_dir output_dir sizes tile_threshold tile_size force v2_output_dir] do |_t, args|
        level0 = Level0.new(
          sizes: args[:sizes] ? args[:sizes].split(/[;,\s]+/) : sizes,
          tile_threshold: args[:tile_threshold] || tile_threshold,
          tile_size: args[:tile_size] || tile_size
        )
        abort "#{name}: libvips is required (e.g. `brew install vips` or `apt-get install libvips-tools`)." unless Vips.available?

        input = args[:input_dir] || input_dir
        output = args[:output_dir] || output_dir
        v2_output = args[:v2_output_dir] || v2_output_dir
        v2_output = nil if v2_output.to_s.empty?
        only_files = only.nil? ? self.class.metadata_images : only
        level0.generate_dir(input, output, force: args[:force] == "true", v2_output_dir: v2_output, only: only_files) do |src, dir, meta|
          next puts("Skipping: #{dir} is up to date") unless meta

          tiles = meta["tiles"] ? ", tiles" : ""
          v2 = v2_output ? " and #{File.join(v2_output, File.basename(dir))}" : ""
          puts "Created: #{dir}#{v2} (#{meta['width']}x#{meta['height']}, #{meta['sizes'].size} sizes#{tiles}) from #{src}"
        end
      end
    end
  end
end
