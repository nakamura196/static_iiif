# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "tmpdir"
require_relative "vips"

module StaticIIIF
  # Writes the files of a IIIF Image API 3 level 0 service for one image, so it
  # can be served from any static host:
  #
  #   <dir>/full/max/0/default.jpg          the full image
  #   <dir>/full/<w>,<h>/0/default.jpg      the full image again (clients ask for it by size)
  #   <dir>/full/<w>,<h>/0/default.jpg      each of `sizes` smaller than the image
  #   <dir>/<region>/<w>,<h>/0/default.jpg  tiles, only when the long side exceeds
  #                                         `tile_threshold` (0 or nil = never)
  #   <dir>/_level0.json                    what was made (see ImageInfo)
  #
  # JPEG sources are linked rather than copied for the two full-size paths,
  # so a repository does not hold the original twice; static site builders
  # (Jekyll included) write the real file on output. Where symlinks are not
  # available the file is copied.
  class Level0
    META_FILE = "_level0.json"
    IMAGE_EXTENSIONS = /\.(jpe?g|png|tiff?)\z/i
    DEFAULTS = { sizes: [256, 1024], tile_threshold: 4000, tile_size: 512 }.freeze

    attr_reader :sizes, :tile_threshold, :tile_size

    def initialize(sizes: DEFAULTS[:sizes], tile_threshold: DEFAULTS[:tile_threshold], tile_size: DEFAULTS[:tile_size])
      @sizes = Array(sizes).map(&:to_i).reject(&:zero?).sort.uniq
      @tile_threshold = tile_threshold.to_i
      @tile_size = tile_size.to_i
    end

    # The metadata written by #generate, or nil if the directory has none.
    def self.read_meta(dir)
      file = File.join(dir, META_FILE)
      File.exist?(file) ? JSON.parse(File.read(file)) : nil
    end

    # Directory name used for an image: its file name without extension, lowercased.
    def self.name_for(path)
      File.basename(path.to_s, ".*").downcase
    end

    # Process every image directly inside input_dir into output_dir/<name>.
    # Yields (source, dir, meta_or_nil) per image; meta is nil when skipped.
    def generate_dir(input_dir, output_dir, force: false)
      images = Dir.children(input_dir).sort.map { |f| File.join(input_dir, f) }
                  .select { |f| File.file?(f) && f.match?(IMAGE_EXTENSIONS) }
      images.map do |src|
        dir = File.join(output_dir, self.class.name_for(src))
        meta = !force && up_to_date?(src, dir) ? nil : generate(src, dir)
        yield src, dir, meta if block_given?
        [src, dir, meta]
      end
    end

    def up_to_date?(src, dir)
      meta = File.join(dir, META_FILE)
      File.exist?(meta) && File.mtime(meta) >= File.mtime(src)
    end

    def generate(src, dir)
      FileUtils.rm_rf(dir)
      width, height = Vips.size(src)

      max_file = File.join(dir, "full", "max", "0", "default.jpg")
      full_file = File.join(dir, "full", "#{width},#{height}", "0", "default.jpg")
      FileUtils.mkdir_p([File.dirname(max_file), File.dirname(full_file)])
      if src.match?(/\.jpe?g\z/i)
        link(src, max_file)
      else
        Vips.run("vips", "copy", src, "#{max_file}[Q=90]")
      end
      link(max_file, full_file)

      made = sizes.select { |w| w < width }.map do |w|
        h = (height * w / width.to_f).round
        out = File.join(dir, "full", "#{w},#{h}", "0", "default.jpg")
        FileUtils.mkdir_p(File.dirname(out))
        Vips.run("vips", "thumbnail", src, "#{out}[Q=85,strip]", w.to_s, "--height", h.to_s, "--size", "force")
        { "width" => w, "height" => h }
      end
      made << { "width" => width, "height" => height }

      meta = { "width" => width, "height" => height, "sizes" => made }
      tiles = tile(src, dir) if tile_threshold.positive? && [width, height].max > tile_threshold
      meta["tiles"] = tiles if tiles
      File.write(File.join(dir, META_FILE), "#{JSON.pretty_generate(meta)}\n")
      meta
    end

    private

    # vips dzsave writes the tile pyramid in the IIIF 3 layout. Its info.json is
    # dropped (ours is written with the right id later), and its full/ folder,
    # which holds the top of the pyramid, is merged beside our sizes.
    def tile(src, dir)
      Dir.mktmpdir do |tmp|
        out = File.join(tmp, "out")
        Vips.run("vips", "dzsave", src, out, "--layout", "iiif3", "--tile-size", tile_size.to_s,
                 "--overlap", "0", "--suffix", ".jpg[Q=85,strip]")
        tiles = JSON.parse(File.read(File.join(out, "info.json")))["tiles"]
        Dir.children(out).each do |entry|
          next if entry == "info.json"

          if entry == "full"
            Dir.children(File.join(out, "full")).each do |size|
              target = File.join(dir, "full", size)
              FileUtils.mv(File.join(out, "full", size), target) unless File.exist?(target)
            end
          else
            FileUtils.mv(File.join(out, entry), File.join(dir, entry))
          end
        end
        tiles
      end
    end

    def link(target, dest)
      rel = Pathname.new(File.expand_path(target)).relative_path_from(Pathname.new(File.expand_path(File.dirname(dest))))
      File.symlink(rel.to_s, dest)
    rescue NotImplementedError, SystemCallError
      FileUtils.cp(target, dest)
    end
  end
end
