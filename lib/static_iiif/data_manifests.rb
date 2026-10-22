# frozen_string_literal: true

require "csv"
require "json"

module StaticIIIF
  # Manifests for the records of a metadata CSV, with the images found in one of
  # two ways:
  #
  # 1. The site's own image files, as CollectionBuilder lists them: an item's
  #    `object_location` (one image), or, for a compound object, the
  #    `object_location` of each child row (`parentid` = the item's id), in
  #    order. Needs `image:` (a callable that describes a site path as an image,
  #    as the Jekyll plugin passes). Rows with a `parentid` are not items, and
  #    rows with a `manifest` (an external one) are left alone.
  #
  # 2. Data files, for images on an existing Image API server. Per item, named
  #    after its id:
  #
  #      <canvases>/<id>.csv   one row per canvas, in order. Columns: label, service
  #                            (the Image API base URL), width, height; optional
  #                            format (default image/jpeg) and profile
  #      <toc>/<id>.txt        a table of contents (see TableOfContents; also used
  #                            with the site's own images)
  #      <annotations>/<id>.csv  text on the canvases (either way of finding the
  #                            images). One row per annotation. Columns: canvas
  #                            (1 for the first), text; optional xywh (a region in
  #                            the image's pixels, "x,y,w,h") and motivation
  #                            (default commenting). Version 3 only
  #
  #    An item with a canvases file uses it, whatever its other columns say.
  #
  # An item without images gets no manifest. The Jekyll plugin runs this for
  # every row of the site's metadata CSV (see StaticIIIF::Jekyll); it can be used
  # on its own too:
  #
  #   dm = StaticIIIF::DataManifests.new(config, source: ".", base_url: "https://example.org",
  #                                      fields: fields,   # rows of config-metadata.csv
  #                                      rows: rows,       # rows of the metadata CSV (for child rows)
  #                                      image: ->(path, version) { ... })   # for the site's own images
  #   dm.manifest?(row)                   # whether it has images
  #   dm.manifest(row).to_h               # version 3
  #   dm.paths(3, row["objectid"])        # ["iiif/3/<id>/manifest.json"]
  #
  # Settings (all optional except where noted; the Jekyll plugin reads them from
  # `static_iiif: manifests:` in _config.yml):
  #
  #   canvases, toc, annotations  directories (default iiif/canvases, iiif/toc,
  #                   iiif/annotations)
  #   v3              output path(s) for version 3; the first is the manifest id
  #                   (default iiif/3/%{id}/manifest.json). %{id} is the item's id
  #   v2              output path(s) for version 2, none by default; the first is the
  #                   id, e.g. [iiif/2/%{id}/manifest, iiif/2/%{id}/manifest.json]
  #   id_column       the id column of the metadata CSV (default objectid)
  #   language        language of the field names, the required statement's label
  #                   and the provider (default none)
  #   value_language  language of the item's own label and summary (default none)
  #   label, summary, viewing_direction, rights, homepage, thumbnail, behavior
  #                   each is a CSV column name, or text with %{column} parts
  #                   (a homepage such as items/%{objectid}.html). A homepage or
  #                   thumbnail without https:// is a path on the site (base_url
  #                   is put in front). Defaults: label title, viewing_direction
  #                   viewing_direction, rights rights; thumbnail image_thumb for
  #                   the site's own images, else the first canvas at
  #                   thumbnail_width (400) pixels. HTML tags are taken out of the summary
  #   required_statement  [label, value], the value a column or text
  #   provider        [name, url] (the Jekyll plugin takes `true` for the site's title and url)
  #   defaults        { viewing_direction:, rights:, behavior: } for rows that leave them empty
  #   service         { version: 2, profile: level1 }, for canvases that give no profile
  #   metadata_skip   fields of config-metadata.csv to leave out of `metadata`
  #   canvas_thumbnail_width  default 200
  #   local_images    false to use only canvases files
  #   parent_column, image_column, canvas_thumbnail, skip_column
  #                   for the site's own images (defaults parentid, object_location,
  #                   image_thumb, manifest)
  class DataManifests
    PLACEHOLDER = /%\{(\w+)\}/
    ABSOLUTE = %r{\A[a-z][a-z0-9+.-]*://}i

    attr_reader :config

    def initialize(config, source: ".", base_url: "", fields: [], rows: [], image: nil)
      @config = config || {}
      @source = source
      @base_url = base_url.to_s.chomp("/")
      @fields = fields.to_a
      @rows = rows.to_a
      @image = image
      @images = {}
    end

    def canvases_path(id)
      File.join(@source, dir(:canvases, "iiif/canvases"), "#{id}.csv")
    end

    def toc_path(id)
      File.join(@source, dir(:toc, "iiif/toc"), "#{id}.txt")
    end

    def annotations_path(id)
      File.join(@source, dir(:annotations, "iiif/annotations"), "#{id}.csv")
    end

    # The ids that have a canvases file (one directory listing, not a lookup per item).
    def available_ids
      @available_ids ||= Dir.glob(File.join(@source, dir(:canvases, "iiif/canvases"), "*.csv"))
                            .to_h { |f| [File.basename(f, ".csv"), true] }
    end

    def id_column
      setting(:id_column) || "objectid"
    end

    # Output paths (relative to the site) for a version, with the id filled in.
    def paths(version, id)
      key = version.to_i == 2 ? :v2 : :v3
      list = Array(setting(key) || (key == :v3 ? "iiif/3/%{id}/manifest.json" : nil))
      list.map { |pattern| pattern.to_s.gsub("%{id}", id.to_s).sub(%r{\A/+}, "") }
    end

    def manifest_id(version, id)
      path = paths(version, id).first
      path && "#{@base_url}/#{path}"
    end

    # Whether the row gets a manifest: it has a canvases file, or is an item with
    # at least one of the site's own images.
    def manifest?(row)
      id = row[id_column].to_s
      return false if id.empty?

      available_ids[id] || !local_canvases(row, 3).empty?
    end

    # A Manifest for one metadata row (see manifest?). Whichever version is
    # written, the id is that version's, so call it per version.
    def manifest(row, version: 3)
      id = row[id_column].to_s
      m = Manifest.new(id: manifest_id(version, id), label: value(:label, row, "title") || id,
                       language: setting(:language) || "none", value_language: setting(:value_language) || "none")
      m.summary = strip_html(value(:summary, row))
      m.viewing_direction = value(:viewing_direction, row, "viewing_direction") || default(:viewing_direction)
      m.rights = value(:rights, row, "rights") || default(:rights)
      m.homepage = absolute(value(:homepage, row))
      m.behavior = value(:behavior, row) || default(:behavior)
      m.required_statement = required_statement(row)
      m.provider = provider
      m.metadata.concat(metadata(row))
      if available_ids[id]
        canvases = read_canvases(canvases_path(id))
        m.thumbnail = absolute(value(:thumbnail, row)) || first_thumbnail(canvases)
      else
        canvases = local_canvases(row, version)
        m.thumbnail = thumbnail(resolve(setting(:thumbnail) || "image_thumb", row), version)
      end
      annotations = version.to_i == 2 ? {} : read_annotations(annotations_path(id))
      canvases.each_with_index do |c, i|
        m.add_canvas(label: c[:label], image: c[:image], thumbnail: c[:thumbnail], annotations: annotations[i + 1])
      end
      toc = toc_path(id)
      m.structures = TableOfContents.parse(File.read(toc, encoding: "UTF-8"), canvases.size) if File.file?(toc)
      m
    end

    private

    # The site's own images of an item: its child rows' images, in order, or its own.
    def local_canvases(row, version)
      return [] unless @image && setting(:local_images) != false
      return [] if blank_to_nil(row[column(:parent_column, "parentid")]) || blank_to_nil(row[column(:skip_column, "manifest")])

      id = row[id_column].to_s
      images = column(:image_column, "object_location")
      parts = children[id] || [row]
      parts.filter_map do |part|
        image = local_image(part[images], version)
        next unless image

        { label: value(:label, part, "title"), image: image,
          thumbnail: thumbnail(part[column(:canvas_thumbnail, "image_thumb")], version) }
      end
    end

    def children
      @children ||= begin
        parent = column(:parent_column, "parentid")
        @rows.each_with_object({}) do |r, out|
          key = blank_to_nil(r[parent])
          (out[key] ||= []) << r if key
        end
      end
    end

    def local_image(path, version)
      path = blank_to_nil(path)
      return nil unless path && @image && !path.match?(ABSOLUTE)

      key = [path, version]
      @images.key?(key) ? @images[key] : (@images[key] = @image.call(path, version))
    end

    # A site path is described from its file (with its size); a URL is kept as it is.
    def thumbnail(path, version)
      local_image(path, version) || (path.to_s.match?(ABSOLUTE) ? path : nil)
    end

    def absolute(url)
      url = blank_to_nil(url)
      return url if url.nil? || url.match?(ABSOLUTE)

      "#{@base_url}/#{url.sub(%r{\A/+}, '')}"
    end

    def provider
      name, url = Array(setting(:provider))
      blank_to_nil(name) && [name.to_s, absolute(url) || "#{@base_url}/"]
    end

    def strip_html(text)
      text && blank_to_nil(text.gsub(/<[^>]*>/, ""))
    end

    def column(key, fallback)
      (setting(key) || fallback).to_s
    end

    def first_thumbnail(canvases)
      service = canvases.first && canvases.first[:image]["service"]
      service && StaticIIIF.thumbnail_url(service, setting(:thumbnail_width) || 400)
    end

    def setting(key)
      config[key.to_s]
    end

    def dir(key, fallback)
      (setting(key) || fallback).to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    def default(key)
      defaults = setting(:defaults)
      defaults.is_a?(Hash) ? blank_to_nil(defaults[key.to_s]) : nil
    end

    def blank_to_nil(value)
      value.to_s.strip.empty? ? nil : value.to_s
    end

    # A setting is a column name, or text that may hold %{column} placeholders.
    def value(key, row, fallback_column = nil)
      spec = setting(key)
      return fallback_column && blank_to_nil(row[fallback_column]) if spec.nil?

      resolve(spec, row)
    end

    def resolve(spec, row)
      return nil if spec.to_s.empty?
      return blank_to_nil(row[spec.to_s]) if row.key?(spec.to_s)

      blank_to_nil(spec.to_s.gsub(PLACEHOLDER) { row[Regexp.last_match(1)].to_s })
    end

    def required_statement(row)
      label, spec = Array(setting(:required_statement))
      text = resolve(spec, row)
      text ? [label, text] : nil
    end

    def metadata(row)
      skip = Array(setting(:metadata_skip)).map(&:to_s)
      @fields.filter_map do |f|
        field = f["field"].to_s
        next if skip.include?(field)

        text = blank_to_nil(row[field])
        text && [blank_to_nil(f["display_name"]) || field, text]
      end
    end

    # { canvas number => [{ "text", "xywh", "motivation" }, ...] }, in the file's order
    def read_annotations(path)
      return {} unless File.file?(path)

      out = Hash.new { |h, k| h[k] = [] }
      CSV.foreach(path, headers: true, encoding: "UTF-8") do |r|
        n = r["canvas"].to_i
        next if n < 1 || blank_to_nil(r["text"]).nil?

        out[n] << { "text" => r["text"], "xywh" => r["xywh"], "motivation" => blank_to_nil(r["motivation"]) }
      end
      out
    end

    def read_canvases(path)
      service = setting(:service).is_a?(Hash) ? setting(:service) : {}
      version = (service["version"] || 2).to_i
      profile = service["profile"] || "level1"
      width = setting(:canvas_thumbnail_width) || 200
      out = []
      CSV.foreach(path, headers: true, encoding: "UTF-8") do |r|
        image = StaticIIIF.external_image(r["service"], width: r["width"], height: r["height"], version: version,
                                          profile: blank_to_nil(r["profile"]) || profile,
                                          format: blank_to_nil(r["format"]) || "image/jpeg")
        out << { label: blank_to_nil(r["label"]), image: image, thumbnail: StaticIIIF.thumbnail_url(r["service"], width) }
      end
      out
    end
  end
end
