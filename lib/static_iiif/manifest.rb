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
  class Manifest
    CONTEXT = "http://iiif.io/api/presentation/3/context.json"
    CONTEXT_V2 = "http://iiif.io/api/presentation/2/context.json"
    RIGHTS_PATTERN = %r{\Ahttps?://(creativecommons\.org|rightsstatements\.org)/}

    attr_accessor :label, :summary, :rights, :required_statement, :homepage, :thumbnail,
                  :viewing_direction, :provider
    attr_reader :id, :language, :metadata, :canvases

    # language: the language of labels and descriptive text ("none" if unknown)
    def initialize(id:, label:, language: "none")
      @id = id
      @label = label
      @language = language.to_s.empty? ? "none" : language.to_s
      @metadata = [] # [label, value] pairs
      @canvases = []
    end

    # image: a Hash with "id", "width", "height" and optional "format", "service"
    # (a level 0 Image API 3 base URL) — as returned by StaticIIIF.image.
    def add_canvas(image:, label: nil, thumbnail: nil)
      @canvases << { image: image, label: label, thumbnail: thumbnail }
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
      h = { "@context" => CONTEXT, "id" => id, "type" => "Manifest", "label" => lang(label) }
      h["summary"] = lang(summary) if present?(summary)
      h["metadata"] = metadata.map { |k, v| { "label" => lang(k), "value" => { "none" => [v.to_s] } } } unless metadata.empty?
      if present?(required_statement)
        label, value = Array(required_statement)
        h["requiredStatement"] = { "label" => lang(label), "value" => { "none" => [value.to_s] } }
      end
      h["rights"] = rights.sub(%r{\Ahttps://creativecommons}, "http://creativecommons") if rights.to_s.match?(RIGHTS_PATTERN)
      h["viewingDirection"] = viewing_direction if %w[left-to-right right-to-left top-to-bottom bottom-to-top].include?(viewing_direction)
      h["homepage"] = [text_resource(homepage, label)] if present?(homepage)
      h["thumbnail"] = [image_resource(thumbnail)] if present?(thumbnail)
      if provider
        name, url = Array(provider)
        h["provider"] = [{ "id" => url, "type" => "Agent", "label" => lang(name), "homepage" => [text_resource(url, name)] }]
      end
      h["items"] = canvases.each_with_index.map { |c, i| canvas(c, i + 1) }
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
      h["thumbnail"] = { "@id" => thumbnail } if present?(thumbnail)
      h["sequences"] = [{
        "@id" => "#{base}/sequence/normal", "@type" => "sc:Sequence",
        "canvases" => canvases.each_with_index.map { |c, i| canvas_v2(c, i + 1) }
      }]
      h
    end

    def canvas_v2(c, n)
      canvas_id = "#{base}/canvas/p#{n}"
      img = c[:image]
      resource = { "@id" => img.fetch("id"), "@type" => "dctypes:Image", "format" => img.fetch("format", "image/jpeg"),
                   "width" => img.fetch("width"), "height" => img.fetch("height") }
      if img["service"]
        resource["service"] = { "@context" => ImageInfo::CONTEXT_V2, "@id" => img["service"],
                                "profile" => "http://iiif.io/api/image/2/level0.json" }
      end
      h = { "@id" => canvas_id, "@type" => "sc:Canvas", "label" => (c[:label] || n).to_s,
            "width" => img.fetch("width"), "height" => img.fetch("height") }
      h["thumbnail"] = { "@id" => c[:thumbnail] } if present?(c[:thumbnail])
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
      body["service"] = [{ "id" => img["service"], "type" => "ImageService3", "profile" => "level0" }] if img["service"]
      h = { "id" => canvas_id, "type" => "Canvas", "label" => { "none" => [(c[:label] || n).to_s] },
            "width" => img.fetch("width"), "height" => img.fetch("height") }
      h["thumbnail"] = [image_resource(c[:thumbnail])] if present?(c[:thumbnail])
      h["items"] = [{
        "id" => "#{canvas_id}/page", "type" => "AnnotationPage",
        "items" => [{ "id" => "#{canvas_id}/page/image", "type" => "Annotation", "motivation" => "painting",
                      "target" => canvas_id, "body" => body }]
      }]
      h
    end

    def lang(value)
      { language => Array(value).map(&:to_s) }
    end

    def text_resource(url, label)
      { "id" => url, "type" => "Text", "label" => lang(label), "format" => "text/html" }
    end

    def image_resource(url)
      { "id" => url, "type" => "Image", "format" => url.to_s.match?(/\.png\z/i) ? "image/png" : "image/jpeg" }
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
