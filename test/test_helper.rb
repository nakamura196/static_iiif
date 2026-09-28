# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "static_iiif"

FIXTURES = File.expand_path("fixtures", __dir__)

module VipsHelper
  def require_vips
    skip "libvips command-line tools not installed" unless StaticIIIF::Vips.available?
  end
end
