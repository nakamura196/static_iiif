# frozen_string_literal: true

require "test_helper"
require "json"
require "static_iiif/jekyll"

module DataSite
  SERVICE = "https://img.example.org/iiif/book"

  CONFIG = {
    "base_url" => "https://app.example.org",
    "v3" => "iiif/3/%{id}/manifest.json",
    "v2" => ["iiif/2/%{id}/manifest", "iiif/2/%{id}/manifest.json"],
    "summary" => "abstract",
    "rights" => "rightsstatement",
    "homepage" => "https://app.example.org/items/%{objectid}.html",
    "required_statement" => ["Attribution", "Example Library"],
    "defaults" => { "viewing_direction" => "left-to-right", "rights" => "https://rightsstatements.org/vocab/CNE/1.0/" },
    "metadata_skip" => ["manifest"]
  }.freeze

  # A site directory with two items that have canvases (one with a table of contents) and one that has none.
  def write_site(dir, config: CONFIG)
    FileUtils.mkdir_p(File.join(dir, "_data"))
    FileUtils.mkdir_p(File.join(dir, "iiif/canvases"))
    FileUtils.mkdir_p(File.join(dir, "iiif/toc"))
    File.write(File.join(dir, "_data/metadata.csv"), <<~CSV)
      objectid,title,creator,abstract,viewing_direction,rightsstatement,image_thumb,manifest
      book1,本一,作者,要旨,right-to-left,https://creativecommons.org/licenses/by/4.0/,#{SERVICE}/001.tif/full/400,/0/default.jpg,x
      book2,"Book, two",,,,,,
      record3,Record,,,,,,
    CSV
    File.write(File.join(dir, "_data/config-metadata.csv"), <<~CSV)
      field,display_name
      title,タイトル / Title
      creator,作成者 / Creator
      manifest,Manifest
    CSV
    File.write(File.join(dir, "iiif/canvases/book1.csv"), <<~CSV)
      label,service,width,height
      1,#{SERVICE}/001.tif,400,300
      "2, verso",#{SERVICE}/002.tif,800,600
      3,#{SERVICE}/003.tif,800,600
    CSV
    File.write(File.join(dir, "iiif/canvases/book2.csv"), <<~CSV)
      label,service,width,height,profile
      ,#{SERVICE}2/001.tif,10,20,level2
    CSV
    File.write(File.join(dir, "iiif/toc/book1.txt"), "r1, 全体, r2;r3\nr2, 上, 1-2\nr3, 下, 3\n")
    config_yml = { "url" => "https://localhost", "plugins" => [], "metadata" => "metadata", "exclude" => ["iiif/"],
                   "static_iiif" => { "manifests" => config } }
    File.write(File.join(dir, "_config.yml"), config_yml.to_yaml)
  end

  def metadata_rows(dir)
    CSV.read(File.join(dir, "_data/metadata.csv"), headers: true).map(&:to_h)
  end

  def fields(dir)
    CSV.read(File.join(dir, "_data/config-metadata.csv"), headers: true).map(&:to_h)
  end
end

class TestDataManifests < Minitest::Test
  include DataSite

  def setup
    @dir = Dir.mktmpdir
    write_site(@dir)
    @rows = metadata_rows(@dir)
    @dm = StaticIIIF::DataManifests.new(CONFIG, source: @dir, base_url: "https://app.example.org/", fields: fields(@dir))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_paths_and_ids
    assert_equal ["iiif/3/book1/manifest.json"], @dm.paths(3, "book1")
    assert_equal %w[iiif/2/book1/manifest iiif/2/book1/manifest.json], @dm.paths(2, "book1")
    assert_equal "https://app.example.org/iiif/2/book1/manifest", @dm.manifest_id(2, "book1")
    assert_equal({ "book1" => true, "book2" => true }, @dm.available_ids)
    assert_equal ["iiif/3/x/manifest.json"], StaticIIIF::DataManifests.new({}).paths(3, "x")
    assert_empty StaticIIIF::DataManifests.new({}).paths(2, "x")
  end

  def test_version_3_manifest
    h = @dm.manifest(@rows[0]).to_h
    assert_equal "https://app.example.org/iiif/3/book1/manifest.json", h["id"]
    assert_equal({ "none" => ["本一"] }, h["label"])
    assert_equal({ "none" => ["要旨"] }, h["summary"])
    assert_equal "right-to-left", h["viewingDirection"]
    assert_equal "http://creativecommons.org/licenses/by/4.0/", h["rights"]
    assert_equal [["タイトル / Title", "本一"], ["作成者 / Creator", "作者"]],
                 h["metadata"].map { |m| [m["label"]["none"][0], m["value"]["none"][0]] }
    assert_equal({ "label" => { "none" => ["Attribution"] }, "value" => { "none" => ["Example Library"] } }, h["requiredStatement"])
    assert_equal "https://app.example.org/items/book1.html", h["homepage"][0]["id"]
    assert_equal "#{SERVICE}/001.tif/full/400,/0/default.jpg", h["thumbnail"][0]["id"]
    assert_equal 3, h["items"].size
    c2 = h["items"][1]
    assert_equal "https://app.example.org/iiif/3/book1/canvas/p2", c2["id"]
    assert_equal({ "none" => ["2, verso"] }, c2["label"])
    assert_equal [800, 600], [c2["width"], c2["height"]]
    assert_equal "#{SERVICE}/002.tif/full/200,/0/default.jpg", c2["thumbnail"][0]["id"]
    body = c2["items"][0]["items"][0]["body"]
    assert_equal "#{SERVICE}/002.tif/full/full/0/default.jpg", body["id"]
    assert_equal "ImageService2", body["service"][0]["@type"]
    assert_equal "http://iiif.io/api/image/2/level1.json", body["service"][0]["profile"]
  end

  def test_structures_from_the_toc_file
    h = @dm.manifest(@rows[0]).to_h
    top = h["structures"][0]
    assert_equal "https://app.example.org/iiif/3/book1/range/r1", top["id"]
    assert_equal %w[r2 r3].map { |r| "https://app.example.org/iiif/3/book1/range/#{r}" }, top["items"].map { |i| i["id"] }
    assert_equal ["https://app.example.org/iiif/2/book1/range/r1"], @dm.manifest(@rows[0], version: 2).to_h(version: 2)["structures"].first(1).map { |r| r["@id"] }
  end

  def test_version_2_manifest
    h = @dm.manifest(@rows[0], version: 2).to_h(version: 2)
    assert_equal "https://app.example.org/iiif/2/book1/manifest", h["@id"]
    assert_equal "Example Library", h["attribution"]
    assert_equal "https://creativecommons.org/licenses/by/4.0/", h["license"]
    assert_equal "要旨", h["description"]
    canvas = h["sequences"][0]["canvases"][0]
    assert_equal "https://app.example.org/iiif/2/book1/canvas/p1", canvas["@id"]
    assert_equal "#{SERVICE}/001.tif/full/full/0/default.jpg", canvas["images"][0]["resource"]["@id"]
  end

  def test_defaults_profile_column_and_unquoted_labels
    h = @dm.manifest(@rows[1]).to_h
    assert_equal({ "none" => ["Book, two"] }, h["label"])
    assert_equal "left-to-right", h["viewingDirection"]
    assert_equal "https://rightsstatements.org/vocab/CNE/1.0/", h["rights"]
    assert_equal "level2", h["items"][0]["items"][0]["items"][0]["body"]["service"][0]["profile"].split("/").last.sub(".json", "")
    assert_equal({ "none" => ["1"] }, h["items"][0]["label"]) # empty label: the number
    refute h.key?("structures")
    refute h.key?("summary")
    assert_equal "#{SERVICE}2/001.tif/full/400,/0/default.jpg", h["thumbnail"][0]["id"] # no thumbnail column value
  end

  def test_image_api_3_services
    dm = StaticIIIF::DataManifests.new(CONFIG.merge("service" => { "version" => 3, "profile" => "level1" }),
                                       source: @dir, base_url: "https://app.example.org")
    body = dm.manifest(@rows[0]).to_h["items"][0]["items"][0]["items"][0]["body"]
    assert_equal "#{SERVICE}/001.tif/full/max/0/default.jpg", body["id"]
    assert_equal [{ "id" => "#{SERVICE}/001.tif", "type" => "ImageService3", "profile" => "level1" }], body["service"]
  end
end

class TestJekyllManifests < Minitest::Test
  include DataSite

  def setup
    @tmp = Dir.mktmpdir
    @src = File.join(@tmp, "site")
    write_site(@src)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def build(overrides = {})
    out = File.join(@tmp, "_site")
    config = Jekyll.configuration({ "source" => @src, "destination" => out, "quiet" => true }.merge(overrides))
    Jekyll::Site.new(config).process
    out
  end

  def test_writes_the_configured_files
    out = build
    assert_equal %w[book1 book2], Dir.children(File.join(out, "iiif/3")).sort
    v3 = JSON.parse(File.read(File.join(out, "iiif/3/book1/manifest.json")))
    assert_equal "https://app.example.org/iiif/3/book1/manifest.json", v3["id"] # not the build's own url
    assert_equal 3, v3["items"].size
    plain = File.read(File.join(out, "iiif/2/book1/manifest"))
    assert_equal plain, File.read(File.join(out, "iiif/2/book1/manifest.json"))
    assert_equal "https://app.example.org/iiif/2/book1/manifest", JSON.parse(plain)["@id"]
    refute File.exist?(File.join(out, "iiif/3/record3"))
    refute File.exist?(File.join(out, "iiif/canvases")) # data stays out of the site
    refute_includes File.read(File.join(out, "iiif/3/book1/manifest.json")), "\n  " # compact by default
  end

  def test_rebuild_and_pretty
    out = build
    mtime = File.mtime(File.join(out, "iiif/3/book1/manifest.json"))
    sleep 0.05
    build
    assert_equal mtime, File.mtime(File.join(out, "iiif/3/book1/manifest.json")) # unchanged content is not rewritten
    out = build("static_iiif" => { "manifests" => CONFIG.merge("pretty" => true) })
    assert_includes File.read(File.join(out, "iiif/3/book1/manifest.json")), "\n  \"id\""
  end

  def test_disabled_and_version_2_off
    out = File.join(@tmp, "_off")
    build("destination" => out, "static_iiif" => { "manifests" => CONFIG.merge("enabled" => false) })
    refute File.exist?(File.join(out, "iiif"))
    out = File.join(@tmp, "_v3")
    build("destination" => out, "static_iiif" => { "manifests" => CONFIG.merge("v2" => []) })
    assert File.exist?(File.join(out, "iiif/3/book1/manifest.json"))
    refute File.exist?(File.join(out, "iiif/2"))
  end

  def test_deeply_nested_table_of_contents
    toc = (1..150).map { |i| "r#{i}, R#{i}, #{i == 150 ? 1 : '-'}#{i == 150 ? '' : ", r#{i + 1}"}" }.join("\n")
    File.write(File.join(@src, "iiif/toc/book2.txt"), toc)
    out = build
    assert_includes File.read(File.join(out, "iiif/3/book2/manifest.json")), "range/r150"
  end
end
