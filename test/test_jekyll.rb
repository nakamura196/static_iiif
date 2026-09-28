# frozen_string_literal: true

require "test_helper"
require "json"
require "static_iiif/jekyll"

class TestJekyll < Minitest::Test
  include VipsHelper

  def setup
    require_vips
    @env = ENV.fetch("JEKYLL_ENV", nil)
    ENV["JEKYLL_ENV"] = "production" # production copies links as real files (see the dev test below)
    @tmp = Dir.mktmpdir
    @src = File.join(@tmp, "site")
    FileUtils.cp_r(File.join(FIXTURES, "site"), @src)
    StaticIIIF::Level0.new(sizes: [256], tile_threshold: 500, tile_size: 256)
                      .generate(File.join(@src, "objects", "big_map.jpg"), File.join(@src, "objects/iiif/3/big_map"))
    config = Jekyll.configuration("source" => @src, "destination" => File.join(@tmp, "_site"), "quiet" => true)
    Jekyll::Site.new(config).process
    @out = File.join(@tmp, "_site")
  end

  def teardown
    ENV["JEKYLL_ENV"] = @env
    FileUtils.rm_rf(@tmp) if @tmp
  end

  def test_info_json_uses_site_url
    info = JSON.parse(File.read(File.join(@out, "objects/iiif/3/big_map/info.json")))
    assert_equal "https://example.org/demo/objects/iiif/3/big_map", info["id"]
    assert_equal 1, info["tiles"][0]["scaleFactors"].first
    refute File.exist?(File.join(@out, "objects/iiif/3/big_map/_level0.json"))
  end

  def test_linked_full_image_is_written_as_a_file
    path = File.join(@out, "objects/iiif/3/big_map/full/max/0/default.jpg")
    refute File.symlink?(path)
    assert_equal [900, 600], StaticIIIF::ImageSize.read(path)
  end

  def test_development_build_keeps_links_that_still_resolve
    ENV["JEKYLL_ENV"] = "development"
    out = File.join(@tmp, "_dev")
    Jekyll::Site.new(Jekyll.configuration("source" => @src, "destination" => out, "quiet" => true)).process
    path = File.join(out, "objects/iiif/3/big_map/full/max/0/default.jpg")
    assert File.symlink?(path)
    assert_equal [900, 600], StaticIIIF::ImageSize.read(path) # points at _dev/objects/big_map.jpg
  end

  def test_filter
    probe = JSON.parse(File.read(File.join(@out, "probe.json")))
    assert_equal "https://example.org/demo/objects/iiif/3/big_map", probe["big"]["service"]
    assert_equal "https://example.org/demo/objects/iiif/3/big_map/full/max/0/default.jpg", probe["big"]["id"]
    assert_equal({ "id" => "https://example.org/demo/objects/Page1.jpg", "width" => 400, "height" => 300,
                   "format" => "image/jpeg" }, probe["page1"])
    assert_nil probe["ext"]
    assert_nil probe["missing"]
  end
end
