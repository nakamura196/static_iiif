# frozen_string_literal: true

require_relative "static_iiif/version"
require_relative "static_iiif/image_size"
require_relative "static_iiif/vips"
require_relative "static_iiif/level0"
require_relative "static_iiif/image_info"
require_relative "static_iiif/manifest"
require_relative "static_iiif/table_of_contents"
require_relative "static_iiif/services"
require_relative "static_iiif/data_manifests"

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
  # full/full for version 2) and carries it; a tiled JPEG has no full size in
  # the service (see Level0), so its body is the file at `url`. Otherwise the
  # size is read from the file header. Returns nil if the size cannot be determined.
  def image(path, url: nil, level0_dir: nil, service_url: nil, version: 3)
    meta = level0_dir && Level0.read_meta(level0_dir)
    if meta && service_url
      service = service_url.to_s.chomp("/")
      full = version.to_i == 2 ? "full" : "max"
      id = meta["sizes"].any? { |s| s["width"] == meta["width"] } ? "#{service}/full/#{full}/0/default.jpg" : url
      return { "id" => id, "width" => meta["width"], "height" => meta["height"],
               "format" => "image/jpeg", "service" => service } if id
    end
    size = path && ImageSize.read(path)
    return nil unless size && url

    format = path.to_s.match?(/\.png\z/i) ? "image/png" : "image/jpeg"
    { "id" => url, "width" => size[0], "height" => size[1], "format" => format }
  end

  # Describe an image that lives on someone else's IIIF Image API server, from
  # its service URL and size alone (no local file). For Manifest#add_canvas.
  #
  #   version  2 or 3, the Image API version of the service
  #   profile  "level1" (default), "level2", ... or a full profile URI
  #
  # The body points at the whole image (full/full for version 2, full/max for
  # version 3) and carries the service with its version and profile.
  def external_image(service_url, width:, height:, version: 2, profile: "level1", format: "image/jpeg")
    service = service_url.to_s.chomp("/")
    full = version.to_i == 2 ? "full" : "max"
    { "id" => "#{service}/full/#{full}/0/default.jpg", "width" => width.to_i, "height" => height.to_i,
      "format" => format, "service" => service, "service_version" => version.to_i == 2 ? 2 : 3,
      "profile" => profile.to_s.empty? ? "level1" : profile.to_s }
  end

  # A thumbnail of that many pixels wide from an Image API service (2 or 3).
  def thumbnail_url(service_url, width = 200)
    "#{service_url.to_s.chomp('/')}/full/#{width},/0/default.jpg"
  end
end
