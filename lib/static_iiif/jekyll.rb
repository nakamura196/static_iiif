# frozen_string_literal: true

require "jekyll"
require "json"
require_relative "../static_iiif"

module StaticIIIF
  # Jekyll plugin. Add `gem "static_iiif"` to the :jekyll_plugins group (or list
  # "static_iiif/jekyll" under `plugins:`). Optional settings in _config.yml:
  #
  #   static_iiif:
  #     images: objects/iiif/3   # where `static-iiif generate` / the rake task wrote
  #                              # the level 0 folders (default shown)
  #
  # It does two things:
  #
  # 1. Writes <images>/<name>/info.json for every level 0 folder, with this
  #    site's url + baseurl, so the same files work in development and production.
  #
  # 2. Adds the Liquid filter `iiif_image`, for writing manifests in templates:
  #
  #      {% assign img = item.object_location | iiif_image %}
  #      "width": {{ img.width }}, "height": {{ img.height }}, "id": {{ img.id | jsonify }}
  #      {% if img.service %}"service": [{ "id": {{ img.service | jsonify }}, ... }]{% endif %}
  #
  #    The argument is a site-relative image path. The level 0 folder is found
  #    by the image's file name (lowercased, without extension). External URLs
  #    and unknown files give nil.
  module Jekyll
    DEFAULT_IMAGES = "objects/iiif/3"

    def self.images_dir(site)
      config = site.config["static_iiif"]
      dir = config.is_a?(Hash) && config["images"] ? config["images"] : DEFAULT_IMAGES
      dir.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    def self.site_url(site, path = "")
      "#{site.config['url']}#{site.config['baseurl']}/#{path.to_s.sub(%r{\A/+}, '')}"
    end

    # A file whose content is produced at build time (no source file, no Liquid).
    class GeneratedFile < ::Jekyll::StaticFile
      def initialize(site, dir, name, content)
        super(site, site.source, dir, name)
        @generated_content = content
      end

      def write(dest)
        path = destination(dest)
        return false if File.exist?(path) && File.read(path, encoding: "UTF-8") == @generated_content

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, @generated_content)
        true
      end
    end

    class InfoJsonGenerator < ::Jekyll::Generator
      safe true

      def generate(site)
        images = Jekyll.images_dir(site)
        Dir.glob(File.join(site.source, images, "*", Level0::META_FILE)).sort.each do |file|
          name = File.basename(File.dirname(file))
          meta = JSON.parse(File.read(file))
          info = ImageInfo.v3(meta, Jekyll.site_url(site, "#{images}/#{name}"))
          site.static_files << GeneratedFile.new(site, "#{images}/#{name}", "info.json", "#{JSON.pretty_generate(info)}\n")
        end
      end
    end

    module Filters
      def iiif_image(path)
        return nil if path.nil? || path.to_s.strip.empty? || path.to_s.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

        site = @context.registers[:site]
        cache = (@context.registers[:static_iiif_cache] ||= {}) # per render, so edits show up in `jekyll serve`
        return cache[path] if cache.key?(path)

        rel = path.to_s.sub(%r{\A/+}, "")
        images = Jekyll.images_dir(site)
        name = Level0.name_for(rel)
        cache[path] = StaticIIIF.image(File.join(site.source, rel), url: Jekyll.site_url(site, rel),
                                       level0_dir: File.join(site.source, images, name),
                                       service_url: Jekyll.site_url(site, "#{images}/#{name}"))
      end
    end
  end
end

Liquid::Template.register_filter(StaticIIIF::Jekyll::Filters)
