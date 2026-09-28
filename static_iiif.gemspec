# frozen_string_literal: true

require_relative "lib/static_iiif/version"

Gem::Specification.new do |spec|
  spec.name = "static_iiif"
  spec.version = StaticIIIF::VERSION
  spec.authors = ["Satoru Nakamura"]
  spec.summary = "IIIF for static sites: level 0 image files (tiles only for large images) and Presentation 3 manifests"
  spec.description = "Publishes local images as IIIF without an image server. Writes IIIF Image API 3 " \
                     "level 0 files with libvips (a few fixed sizes; tiles only above a size threshold), " \
                     "info.json with the site's own URL, and Presentation 3 manifests. Includes a command, " \
                     "a Rake task and a Jekyll plugin (with a Liquid filter for manifest templates)."
  spec.homepage = "https://github.com/nakamura196/static_iiif"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["static-iiif"]
  spec.require_paths = ["lib"]
end
