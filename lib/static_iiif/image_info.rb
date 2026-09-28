# frozen_string_literal: true

module StaticIIIF
  # The info.json of a level 0 image service (Image API 3 or 2), from the
  # metadata Level0 wrote.
  # `id` is the service's base URL (the directory holding full/ and the tiles);
  # it is supplied at publish time so the same files work on any host.
  module ImageInfo
    CONTEXT_V3 = "http://iiif.io/api/image/3/context.json"
    CONTEXT_V2 = "http://iiif.io/api/image/2/context.json"

    module_function

    def v3(meta, id)
      info = {
        "@context" => CONTEXT_V3,
        "id" => id.to_s.chomp("/"),
        "type" => "ImageService3",
        "protocol" => "http://iiif.io/api/image",
        "profile" => "level0",
        "width" => meta.fetch("width"),
        "height" => meta.fetch("height"),
        "sizes" => meta.fetch("sizes")
      }
      info["tiles"] = meta["tiles"] if meta["tiles"]
      info
    end

    def v2(meta, id)
      info = {
        "@context" => CONTEXT_V2,
        "@id" => id.to_s.chomp("/"),
        "protocol" => "http://iiif.io/api/image",
        "width" => meta.fetch("width"),
        "height" => meta.fetch("height"),
        "profile" => ["http://iiif.io/api/image/2/level0.json"],
        "sizes" => meta.fetch("sizes")
      }
      info["tiles"] = meta["tiles"] if meta["tiles"]
      info
    end

    def for_version(version, meta, id)
      version.to_i == 2 ? v2(meta, id) : v3(meta, id)
    end
  end
end
