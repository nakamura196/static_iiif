# frozen_string_literal: true

require "test_helper"

class TestImageInfo < Minitest::Test
  def test_v3
    meta = { "width" => 900, "height" => 600, "sizes" => [{ "width" => 900, "height" => 600 }] }
    info = StaticIIIF::ImageInfo.v3(meta, "https://example.org/iiif/3/big/")
    assert_equal "https://example.org/iiif/3/big", info["id"]
    assert_equal "ImageService3", info["type"]
    assert_equal "level0", info["profile"]
    refute info.key?("tiles")
    tiled = StaticIIIF::ImageInfo.v3(meta.merge("tiles" => [{ "width" => 512, "scaleFactors" => [1, 2] }]), "x")
    assert_equal 512, tiled["tiles"].first["width"]
  end
end
