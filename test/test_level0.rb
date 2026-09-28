# frozen_string_literal: true

require "test_helper"

class TestLevel0 < Minitest::Test
  include VipsHelper

  def setup
    require_vips
    @tmp = Dir.mktmpdir
    @objects = File.join(FIXTURES, "site", "objects")
  end

  def teardown
    FileUtils.rm_rf(@tmp) if @tmp
  end

  def jpg(dir, size)
    File.join(dir, "full", size, "0", "default.jpg")
  end

  def test_small_image_gets_sizes_but_no_tiles
    dir = File.join(@tmp, "page1")
    meta = StaticIIIF::Level0.new(sizes: [100, 256, 1024], tile_threshold: 4000).generate(File.join(@objects, "Page1.jpg"), dir)
    assert_equal({ "width" => 400, "height" => 300 }, meta.slice("width", "height"))
    assert_equal [[100, 75], [256, 192], [400, 300]], meta["sizes"].map { |s| [s["width"], s["height"]] }
    refute meta.key?("tiles")
    assert_equal [256, 192], StaticIIIF::ImageSize.read(jpg(dir, "256,192"))
    # the full image, by name and by size, is the original
    assert_equal File.binread(File.join(@objects, "Page1.jpg")), File.binread(jpg(dir, "max"))
    assert_equal File.binread(jpg(dir, "max")), File.binread(jpg(dir, "400,300"))
    assert_equal meta, StaticIIIF::Level0.read_meta(dir)
    assert_empty Dir.glob(File.join(dir, "*,*,*,*"))
  end

  def test_full_image_is_linked_not_copied
    dir = File.join(@tmp, "page1")
    StaticIIIF::Level0.new.generate(File.join(@objects, "Page1.jpg"), dir)
    assert File.symlink?(jpg(dir, "max"))
    refute File.readlink(jpg(dir, "max")).start_with?("/"), "link should be relative"
  end

  def test_large_image_gets_tiles_and_top_level
    dir = File.join(@tmp, "big")
    meta = StaticIIIF::Level0.new(sizes: [256], tile_threshold: 500, tile_size: 256).generate(File.join(@objects, "big_map.jpg"), dir)
    tiles = meta["tiles"].first
    assert_equal 256, tiles["width"]
    assert_equal 1, tiles["scaleFactors"].first # how many levels vips makes depends on its version
    assert File.exist?(File.join(dir, "0,0,256,256", "256,256", "0", "default.jpg"))
    # The first tile of the top advertised level must exist. When that level fits
    # in one tile its region is the whole image, written as full/<w>,<h> (vips puts
    # it under full/, and it must survive next to our sizes).
    f = tiles["scaleFactors"].last
    w = [256 * f, 900].min
    h = [256 * f, 600].min
    region = w == 900 && h == 600 ? "full" : "0,0,#{w},#{h}"
    top = File.join(dir, region, "#{(w.to_f / f).ceil},#{(h.to_f / f).ceil}", "0", "default.jpg")
    assert File.exist?(top), "top level for scale #{f}: #{top}"
    refute File.exist?(File.join(dir, "info.json"))
  end

  def test_generate_dir_skips_up_to_date_images
    level0 = StaticIIIF::Level0.new(tile_threshold: 0)
    first = level0.generate_dir(@objects, @tmp).map { |_, dir, meta| [File.basename(dir), !meta.nil?] }
    assert_equal [["page1", true], ["big_map", true]], first # sorted by file name: Page1.jpg, big_map.jpg
    second = level0.generate_dir(@objects, @tmp).map { |_, _, meta| meta }
    assert_equal [nil, nil], second
    assert(level0.generate_dir(@objects, @tmp, force: true).all? { |_, _, meta| meta })
  end

  def test_derive_v2_links_into_the_v3_folder
    v3 = File.join(@tmp, "3", "big")
    v2 = File.join(@tmp, "2", "big")
    meta = StaticIIIF::Level0.new(sizes: [256], tile_threshold: 500, tile_size: 256).generate(File.join(@objects, "big_map.jpg"), v3)
    assert_equal meta, StaticIIIF::Level0.derive_v2(v3, v2)
    assert_equal meta, StaticIIIF::Level0.read_meta(v2)
    # the full size by name (2.0 "full", 2.1 "max") and by width; the original, not a link to a link
    %w[full max 900,].each do |size|
      path = jpg(v2, size)
      assert File.symlink?(path), size
      assert_equal File.expand_path(File.join(@objects, "big_map.jpg")), File.expand_path(File.readlink(path), File.dirname(path))
    end
    assert_equal [256, 171], StaticIIIF::ImageSize.read(jpg(v2, "256,"))
    # tiles: <w>,<h> in version 3 is <w>, in version 2
    assert File.exist?(File.join(v2, "0,0,256,256", "256,", "0", "default.jpg"))
    assert_empty Dir.glob(File.join(v2, "*", "*,[0-9]*"))
  end

  def test_generate_dir_with_v2
    level0 = StaticIIIF::Level0.new(tile_threshold: 0)
    v3 = File.join(@tmp, "3")
    v2 = File.join(@tmp, "2")
    level0.generate_dir(@objects, v3, v2_output_dir: v2)
    assert File.exist?(jpg(File.join(v2, "page1"), "full"))
    assert_equal([nil, nil], level0.generate_dir(@objects, v3, v2_output_dir: v2).map { |_, _, meta| meta })
    # a missing version 2 folder is made even when version 3 is up to date
    FileUtils.rm_rf(File.join(v2, "page1"))
    made = level0.generate_dir(@objects, v3, v2_output_dir: v2).map { |_, _, meta| !meta.nil? }
    assert_equal [true, false], made
    assert File.exist?(jpg(File.join(v2, "page1"), "400,"))
  end
end
