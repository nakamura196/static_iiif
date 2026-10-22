# frozen_string_literal: true

module StaticIIIF
  # Builds a IIIF Presentation 3 (or 2) manifest from plain values, for tools
  # that do not have their own template (the Jekyll plugin's users can also
  # write the manifest in Liquid with the `iiif_image` filter instead).
  #
  #   m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/3/book1/manifest.json",
  #                                label: "Book 1", language: "en")
  #   m.metadata << ["Creator", "Anonymous"]
  #   m.add_canvas(label: "p. 1", image: StaticIIIF.image("objects/p1.jpg", url: ..., service: ...))
  #   JSON.pretty_generate(m.to_h)
  #
  # to_h(version: 2) gives Presentation 2 instead. Give it an id under a
  # separate path (e.g. .../iiif/2/book1/manifest.json) and images described
  # with StaticIIIF.image(..., version: 2). Version 2 has fewer fields: labels
  # and values are plain strings (the language is not recorded), rights and
  # required_statement become license and attribution, homepage becomes
  # related, and provider is left out.
  #
  # Canvas ids are <manifest id without its file name>/canvas/p<n>.
  #
  # Table of contents: `structures` holds ranges (see TableOfContents.parse for
  # the shape). They are written as nested Range objects in version 3 and as a
  # flat list of sc:Range in version 2; ids are <base>/range/<id>.
  class Manifest
    CONTEXT = "http://iiif.io/api/presentation/3/context.json"
    CONTEXT_V2 = "http://iiif.io/api/presentation/2/context.json"
    RIGHTS_PATTERN = %r{\Ahttps?://(creativecommons\.org|rightsstatements\.org)/}

    # behavior: how viewers lay out the canvases — "individuals" (one at a time),
    # "paged" (a book, two side by side) or "continuous" (a scroll); written as
    # `behavior` in version 3 and as the sequence's `viewingHint` in version 2.
    BEHAVIORS = %w[individuals paged continuous].freeze

    attr_accessor :label, :summary, :rights, :required_statement, :homepage, :thumbnail,
                  :viewing_direction, :provider, :behavior
    attr_accessor :structures
    attr_reader :id, :language, :metadata, :canvases

    # language: the language of labels and descriptive text ("none" if unknown)
    # value_language: the language of the item's own text (its label, summary and
    # table of contents), when it differs from that of the field names and the
    # provider, e.g. "none" for Japanese records on an English site. Default: language
    def initialize(id:, label:, language: "none", value_language: nil)
      @id = id
      @label = label
      @language = language.to_s.empty? ? "none" : language.to_s
      @value_language = value_language.to_s.empty? ? @language : value_language.to_s
      @metadata = [] # [label, value] pairs
      @canvases = []
      @structures = [] # ranges: { id:, label:, canvases: [n, ...], ranges: [id, ...], top: }
    end

    # image: a Hash with "id", "width", "height" and optional "format", "service"
    # (an Image API base URL; level 0 version 3 unless the Hash says otherwise)
    # — as returned by StaticIIIF.image or StaticIIIF.external_image. A service
    # on another server carries "service_version" (2 or 3) and "profile"
    # ("level1" or a full profile URI).
    #
    # annotations: text on the canvas, each a Hash with "text" and optional
    # "xywh" (a region, "x,y,w,h" in the image's pixels; the whole canvas if
    # empty) and "motivation" (default "commenting"). Written in version 3 only,
    # as one AnnotationPage in the canvas's `annotations`.
    def add_canvas(image:, label: nil, thumbnail: nil, annotations: [])
      @canvases << { image: image, label: label, thumbnail: thumbnail, annotations: annotations || [] }
      self
    end

    def base
      id.sub(%r{/[^/]*\z}, "")
    end

    def to_h(version: 3)
      version.to_i == 2 ? to_v2 : to_v3
    end

    private

    def to_v3
      h = { "@context" => CONTEXT, "id" => id, "type" => "Manifest", "label" => value_lang(label) }
      h["summary"] = value_lang(summary) if present?(summary)
      h["metadata"] = metadata.map { |k, v| { "label" => lang(k), "value" => { "none" => [v.to_s] } } } unless metadata.empty?
      if present?(required_statement)
        statement_label, statement = Array(required_statement)
        h["requiredStatement"] = { "label" => lang(statement_label), "value" => { "none" => [statement.to_s] } }
      end
      h["rights"] = rights.sub(%r{\Ahttps://creativecommons}, "http://creativecommons") if rights.to_s.match?(RIGHTS_PATTERN)
      h["viewingDirection"] = viewing_direction if %w[left-to-right right-to-left top-to-bottom bottom-to-top].include?(viewing_direction)
      h["behavior"] = [behavior.to_s] if BEHAVIORS.include?(behavior.to_s)
      h["homepage"] = [text_resource(homepage, value_lang(label))] if present?(homepage)
      h["thumbnail"] = [image_resource(thumbnail)] if present?(thumbnail)
      if provider
        name, url = Array(provider)
        h["provider"] = [{ "id" => url, "type" => "Agent", "label" => lang(name), "homepage" => [text_resource(url, lang(name))] }]
      end
      h["items"] = canvases.each_with_index.map { |c, i| canvas(c, i + 1) }
      h["structures"] = structures_v3 unless structures.empty?
      h
    end

    def to_v2
      h = { "@context" => CONTEXT_V2, "@id" => id, "@type" => "sc:Manifest", "label" => text(label) }
      h["description"] = text(summary) if present?(summary)
      h["metadata"] = metadata.map { |k, v| { "label" => text(k), "value" => v.to_s } } unless metadata.empty?
      h["attribution"] = Array(required_statement).last.to_s if present?(required_statement)
      h["license"] = rights if rights.to_s.match?(RIGHTS_PATTERN)
      h["viewingDirection"] = viewing_direction if %w[left-to-right right-to-left top-to-bottom bottom-to-top].include?(viewing_direction)
      h["related"] = { "@id" => homepage, "format" => "text/html" } if present?(homepage)
      h["thumbnail"] = image_resource_v2(thumbnail) if present?(thumbnail)
      sequence = { "@id" => "#{base}/sequence/normal", "@type" => "sc:Sequence" }
      sequence["viewingHint"] = behavior.to_s if BEHAVIORS.include?(behavior.to_s)
      sequence["canvases"] = canvases.each_with_index.map { |c, i| canvas_v2(c, i + 1) }
      h["sequences"] = [sequence]
      h["structures"] = structures_v2 unless structures.empty?
      h
    end

    def service_v3(img)
      if img["service_version"].to_i == 2
        { "@context" => ImageInfo::CONTEXT_V2, "@id" => img["service"], "@type" => "ImageService2",
          "profile" => profile_v2(img["profile"]) }
      else
        { "id" => img["service"], "type" => "ImageService3", "profile" => profile_v3(img["profile"]) }
      end
    end

    def service_v2(img)
      if img["service_version"].to_i == 3
        { "@context" => ImageInfo::CONTEXT_V3, "@id" => img["service"], "profile" => profile_v3(img["profile"]) }
      else
        { "@context" => ImageInfo::CONTEXT_V2, "@id" => img["service"], "profile" => profile_v2(img["profile"]) }
      end
    end

    # Image API 2 names its profile by URI, version 3 by "level0" / "level1" / "level2".
    def profile_v2(profile)
      profile = profile.to_s
      return "http://iiif.io/api/image/2/level0.json" if profile.empty?

      profile.match?(%r{\Ahttps?://}) ? profile : "http://iiif.io/api/image/2/#{profile}.json"
    end

    def profile_v3(profile)
      profile = profile.to_s
      return "level0" if profile.empty?

      profile[%r{/(level[012])\.json\z}, 1] || profile
    end

    def structures_v3
      by_id = structures.to_h { |r| [r[:id], r] }
      referenced = structures.flat_map { |r| r[:ranges] || [] }
      roots = structures.map { |r| r[:id] }.reject { |rid| referenced.include?(rid) }
      roots = [structures.first[:id]] if roots.empty?
      visited = {}
      build = lambda do |rid|
        visited[rid] = true
        r = by_id[rid]
        items = (r[:canvases] || []).map { |n| { "id" => "#{base}/canvas/p#{n}", "type" => "Canvas" } }
        (r[:ranges] || []).each { |child| items << build.call(child) if by_id.key?(child) && !visited[child] }
        { "id" => "#{base}/range/#{rid}", "type" => "Range", "label" => value_lang(r[:label]), "items" => items }
      end
      roots.each_with_object([]) { |rid, out| out << build.call(rid) unless visited[rid] }
    end

    def structures_v2
      structures.map do |r|
        h = { "@id" => "#{base}/range/#{r[:id]}", "@type" => "sc:Range", "label" => text(r[:label]) }
        h["viewingHint"] = "top" if r[:top]
        h["ranges"] = r[:ranges].map { |rid| "#{base}/range/#{rid}" } unless (r[:ranges] || []).empty?
        h["canvases"] = r[:canvases].map { |n| "#{base}/canvas/p#{n}" } unless (r[:canvases] || []).empty?
        h
      end
    end

    def canvas_v2(c, n)
      canvas_id = "#{base}/canvas/p#{n}"
      img = c[:image]
      resource = { "@id" => img.fetch("id"), "@type" => "dctypes:Image", "format" => img.fetch("format", "image/jpeg"),
                   "width" => img.fetch("width"), "height" => img.fetch("height") }
      resource["service"] = service_v2(img) if img["service"]
      h = { "@id" => canvas_id, "@type" => "sc:Canvas", "label" => (c[:label] || n).to_s,
            "width" => img.fetch("width"), "height" => img.fetch("height") }
      h["thumbnail"] = image_resource_v2(c[:thumbnail]) if present?(c[:thumbnail])
      h["images"] = [{ "@id" => "#{canvas_id}/image", "@type" => "oa:Annotation", "motivation" => "sc:painting",
                       "on" => canvas_id, "resource" => resource }]
      h
    end

    def text(value)
      Array(value).map(&:to_s).join(" ")
    end

    def canvas(c, n)
      canvas_id = "#{base}/canvas/p#{n}"
      img = c[:image]
      body = { "id" => img.fetch("id"), "type" => "Image", "format" => img.fetch("format", "image/jpeg"),
               "width" => img.fetch("width"), "height" => img.fetch("height") }
      body["service"] = [service_v3(img)] if img["service"]
      h = { "id" => canvas_id, "type" => "Canvas", "label" => { "none" => [(c[:label] || n).to_s] },
            "width" => img.fetch("width"), "height" => img.fetch("height") }
      h["thumbnail"] = [image_resource(c[:thumbnail])] if present?(c[:thumbnail])
      h["items"] = [{
        "id" => "#{canvas_id}/page", "type" => "AnnotationPage",
        "items" => [{ "id" => "#{canvas_id}/page/image", "type" => "Annotation", "motivation" => "painting",
                      "target" => canvas_id, "body" => body }]
      }]
      annos = c[:annotations] || []
      h["annotations"] = [annotation_page(canvas_id, annos)] unless annos.empty?
      h
    end

    def annotation_page(canvas_id, annos)
      items = annos.each_with_index.map do |a, i|
        xywh = a["xywh"].to_s.delete(" ")
        body = { "type" => "TextualBody", "value" => a.fetch("text").to_s, "format" => "text/plain" }
        body["language"] = @value_language unless @value_language == "none"
        { "id" => "#{canvas_id}/annotation/#{i + 1}", "type" => "Annotation",
          "motivation" => present?(a["motivation"]) ? a["motivation"].to_s : "commenting",
          "body" => body, "target" => xywh.empty? ? canvas_id : "#{canvas_id}#xywh=#{xywh}" }
      end
      { "id" => "#{canvas_id}/annotations", "type" => "AnnotationPage", "items" => items }
    end

    def lang(value)
      { language => Array(value).map(&:to_s) }
    end

    def value_lang(value)
      { @value_language => Array(value).map(&:to_s) }
    end

    # label: a language map
    def text_resource(url, label)
      { "id" => url, "type" => "Text", "label" => label, "format" => "text/html" }
    end

    # A thumbnail is a URL, or a Hash with "id" and, if known, "width", "height"
    # and "format" (as StaticIIIF.image returns for a local file).
    def image_resource(thumb)
      url, width, height, format = thumbnail_parts(thumb)
      h = { "id" => url, "type" => "Image", "format" => format }
      h["width"] = width if width
      h["height"] = height if height
      h
    end

    def image_resource_v2(thumb)
      url, _width, _height, format = thumbnail_parts(thumb)
      { "@id" => url, "@type" => "dctypes:Image", "format" => format }
    end

    def thumbnail_parts(thumb)
      if thumb.is_a?(Hash)
        url = thumb["id"]
        [url, thumb["width"], thumb["height"], thumb["format"] || image_format(url)]
      else
        [thumb, nil, nil, image_format(thumb)]
      end
    end

    def image_format(url)
      url.to_s.match?(/\.png\z/i) ? "image/png" : "image/jpeg"
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
