# frozen_string_literal: true

module StaticIIIF
  # The info.json of a level 0 image service, from the metadata Level0 wrote.
  # `id` is the service's base URL (the directory holding full/ and the tiles);
  # it is supplied at publish time so the same files work on any host.
  module ImageInfo
    CONTEXT_V3 = "http://iiif.io/api/image/3/context.json"

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
  end
end
