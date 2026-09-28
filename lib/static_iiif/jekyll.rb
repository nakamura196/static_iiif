# frozen_string_literal: true

require "jekyll"
require "json"
require_relative "../static_iiif"

module StaticIIIF
  # Jekyll plugin. Add `gem "static_iiif"` to the :jekyll_plugins group (or list
  # "static_iiif/jekyll" under `plugins:`). Optional settings in _config.yml:
  #
  #   static_iiif:
  #     images: objects/iiif/3     # where `static-iiif generate` / the rake task wrote
  #                                # the level 0 folders (default shown)
  #     images_v2: objects/iiif/2  # the Image API 2 folders, if made (default shown)
  #
  # It does two things:
  #
  # 1. Writes <images>/<name>/info.json for every level 0 folder (and the
  #    version 2 info.json in <images_v2>/<name>/), with this site's
  #    url + baseurl, so the same files work in development and production.
  #
  # 2. Adds the Liquid filter `iiif_image`, for writing manifests in templates:
  #
  #      {% assign img = item.object_location | iiif_image %}
  #      "width": {{ img.width }}, "height": {{ img.height }}, "id": {{ img.id | jsonify }}
  #      {% if img.service %}"service": [{ "id": {{ img.service | jsonify }}, ... }]{% endif %}
  #
  #    The argument is a site-relative image path. The level 0 folder is found
  #    by the image's file name (lowercased, without extension). External URLs
  #    and unknown files give nil. `iiif_image: 2` describes the image for a
  #    Presentation 2 manifest (the service is then the version 2 folder).
  module Jekyll
    DEFAULT_IMAGES = { 3 => "objects/iiif/3", 2 => "objects/iiif/2" }.freeze
    CONFIG_KEYS = { 3 => "images", 2 => "images_v2" }.freeze

    def self.images_dir(site, version = 3)
      version = version.to_i == 2 ? 2 : 3
      config = site.config["static_iiif"]
      key = CONFIG_KEYS[version]
      dir = config.is_a?(Hash) && config[key] ? config[key] : DEFAULT_IMAGES[version]
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
        [3, 2].each do |version|
          images = Jekyll.images_dir(site, version)
          Dir.glob(File.join(site.source, images, "*", Level0::META_FILE)).sort.each do |file|
            name = File.basename(File.dirname(file))
            meta = JSON.parse(File.read(file))
            info = ImageInfo.for_version(version, meta, Jekyll.site_url(site, "#{images}/#{name}"))
            site.static_files << GeneratedFile.new(site, "#{images}/#{name}", "info.json", "#{JSON.pretty_generate(info)}\n")
          end
        end
      end
    end

    module Filters
      def iiif_image(path, version = 3)
        return nil if path.nil? || path.to_s.strip.empty? || path.to_s.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

        version = version.to_i == 2 ? 2 : 3
        site = @context.registers[:site]
        cache = (@context.registers[:static_iiif_cache] ||= {}) # per render, so edits show up in `jekyll serve`
        key = [path, version]
        return cache[key] if cache.key?(key)

        rel = path.to_s.sub(%r{\A/+}, "")
        images = Jekyll.images_dir(site, version)
        name = Level0.name_for(rel)
        cache[key] = StaticIIIF.image(File.join(site.source, rel), url: Jekyll.site_url(site, rel),
                                      level0_dir: File.join(site.source, images, name),
                                      service_url: Jekyll.site_url(site, "#{images}/#{name}"), version: version)
      end
    end
  end
end

Liquid::Template.register_filter(StaticIIIF::Jekyll::Filters)
