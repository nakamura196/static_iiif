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
  # It does three things:
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
  # 3. Optionally writes the item manifests, from the site's own images (as
  #    CollectionBuilder lists them in the metadata CSV) or from data files for
  #    images served by another IIIF server (see DataManifests for both and the settings):
  #
  #      static_iiif:
  #        manifests:
  #          v3: iiif/3/%{id}/manifest.json
  #          v2: iiif/2/%{id}/manifest.json
  #          label: title
  #          summary: description
  #          rights: rightsstatement
  #          homepage: items/%{objectid}.html     # a path on the site, or a full URL
  #          provider: true                       # the site's title and url
  #          required_statement: [Rights, rights]
  #          metadata_skip: [title, description, manifest]
  #          base_url: https://example.org        # for the ids (default: url + baseurl; a path is put after url)
  #          canvases: iiif/canvases              # <id>.csv per item, for images elsewhere
  #          toc: iiif/toc                        # <id>.txt per item (optional)
  #          enabled: false                       # e.g. in the config of a second build
  #          write: false                         # or: a second build links to the first one's
  #                                               # manifests (base_url) and writes none
  #
  #    Every row of the site's metadata CSV (`metadata:` in _config.yml) that has
  #    images gets a manifest, with `metadata` from _data/config-metadata.csv.
  #    Keep the data directories out of the published site (`exclude:`).
  #
  # 4. Adds the Liquid filter `iiif_manifest`, the URL of an item's manifest made
  #    in 3 (nil if it has none), for a viewer on the item page:
  #
  #      {% assign manifest = page.objectid | iiif_manifest %}   {% comment %} or iiif_manifest: 2 {% endcomment %}
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

    # Describe an image on the site by its path (see StaticIIIF.image): its level 0
    # folder, found by file name, if there is one, else the file itself.
    def self.image(site, path, version = 3)
      version = version.to_i == 2 ? 2 : 3
      rel = path.to_s.sub(%r{\A/+}, "")
      images = images_dir(site, version)
      name = Level0.name_for(rel)
      StaticIIIF.image(File.join(site.source, rel), url: site_url(site, rel),
                       level0_dir: File.join(site.source, images, name),
                       service_url: site_url(site, "#{images}/#{name}"), version: version)
    end

    # The manifests ManifestGenerator made, per site: { version => { item id => url } }
    def self.manifests(site)
      # kept on the site: a WeakMap also drops its values, so the table vanished when
      # nothing else held it (a build with `write: false`)
      site.instance_variable_get(:@static_iiif_manifests) ||
        site.instance_variable_set(:@static_iiif_manifests, { 3 => {}, 2 => {} })
    end

    # A file whose content is produced at build time (no source file, no Liquid).
    # The content is a String, or an object with `call` that makes it when the file is written
    # (so thousands of manifests are never held in memory together).
    class GeneratedFile < ::Jekyll::StaticFile
      def initialize(site, dir, name, content)
        super(site, site.source, dir, name)
        @generated_content = content
      end

      def write(dest)
        path = destination(dest)
        content = @generated_content.respond_to?(:call) ? @generated_content.call : @generated_content
        return false if File.exist?(path) && File.read(path, encoding: "UTF-8") == content

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        true
      end
    end

    # One manifest's JSON, made on first use and handed to each of the files that carry it
    # (version 2 is written at two paths); dropped after the last one.
    class SharedContent
      def initialize(uses, &build)
        @uses = uses
        @build = build
      end

      def call
        @value ||= @build.call
        value = @value
        @value = nil if (@uses -= 1) <= 0
        value
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

    class ManifestGenerator < ::Jekyll::Generator
      safe true
      priority :low

      def generate(site)
        config = site.config["static_iiif"]
        config = config["manifests"] if config.is_a?(Hash)
        return unless config.is_a?(Hash) && config["enabled"] != false

        made = Jekyll.manifests(site)
        made.each_value(&:clear)
        base_url = config["base_url"] || site.config["baseurl"].to_s
        # a path (e.g. the first build's baseurl) is on this site's url, so local builds stay local
        base_url = "#{site.config['url']}#{base_url}" unless base_url.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        config = config.merge("provider" => [site.config["title"], "/"]) if config["provider"] == true
        fields = site.data[config["metadata_config"] || "config-metadata"]
        rows = site.data[site.config["metadata"]]
        return unless rows.is_a?(Array)

        manifests = DataManifests.new(config, source: site.source, base_url: base_url, fields: fields.is_a?(Array) ? fields : [],
                                              rows: rows, image: ->(path, version) { Jekyll.image(site, path, version) })
        rows.each do |row|
          next unless manifests.manifest?(row)

          id = row[manifests.id_column].to_s
          [3, 2].each do |version|
            # write: false links to the manifests of another build (base_url) without writing them
            if config["write"] == false
              url = manifests.manifest_id(version, id)
              made[version][id] = url if url
            else
              add(site, manifests, row, id, version, made)
            end
          end
        end
      end

      private

      def add(site, manifests, row, id, version, made)
        paths = manifests.paths(version, id)
        return if paths.empty?

        made[version][id] = manifests.manifest_id(version, id)
        pretty = manifests.config["pretty"] == true
        json = SharedContent.new(paths.size) do
          h = manifests.manifest(row, version: version).to_h(version: version)
          # a table of contents can nest deeper than the default limit of 100
          pretty ? "#{JSON.pretty_generate(h, max_nesting: false)}\n" : JSON.generate(h, max_nesting: false)
        end
        paths.each { |path| site.static_files << GeneratedFile.new(site, File.dirname(path), File.basename(path), json) }
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

        cache[key] = Jekyll.image(site, path, version)
      end

      def iiif_manifest(id, version = 3)
        Jekyll.manifests(@context.registers[:site])[version.to_i == 2 ? 2 : 3][id.to_s]
      end
    end
  end
end

Liquid::Template.register_filter(StaticIIIF::Jekyll::Filters)
