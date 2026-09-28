# frozen_string_literal: true

require_relative "static_iiif/version"
require_relative "static_iiif/image_size"
require_relative "static_iiif/vips"
require_relative "static_iiif/level0"
require_relative "static_iiif/image_info"
require_relative "static_iiif/manifest"

# Static IIIF for sites without an image server: IIIF Image API level 0 files
# (fixed sizes, tiles only for large images) and manifests, in version 3 and,
# optionally, version 2.
module StaticIIIF
  module_function

  # Describe one image as a manifest body (a Hash for Manifest#add_canvas).
  #
  #   path        the local image file
  #   url         its public URL, used when there is no level 0 service
  #   level0_dir  the directory Level0#generate wrote for it (optional)
  #   service_url that directory's public URL (required with level0_dir)
  #
  #   version     3, or 2 when level0_dir is an Image API 2 folder (Level0.derive_v2)
  #
  # With level 0 files the body points into the service (full/max, or
  # full/full for version 2) and carries it; otherwise the size is read from
  # the file header. Returns nil if the size cannot be determined.
  def image(path, url: nil, level0_dir: nil, service_url: nil, version: 3)
    meta = level0_dir && Level0.read_meta(level0_dir)
    if meta && service_url
      service = service_url.to_s.chomp("/")
      full = version.to_i == 2 ? "full" : "max"
      return { "id" => "#{service}/full/#{full}/0/default.jpg", "width" => meta["width"], "height" => meta["height"],
               "format" => "image/jpeg", "service" => service }
    end
    size = path && ImageSize.read(path)
    return nil unless size && url

    format = path.to_s.match?(/\.png\z/i) ? "image/png" : "image/jpeg"
    { "id" => url, "width" => size[0], "height" => size[1], "format" => format }
  end
end
