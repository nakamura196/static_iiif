# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"
require "static_iiif/jekyll"

# Manifests from the site's own images, listed as CollectionBuilder lists them.
class TestLocalManifests < Minitest::Test
  BASE = "https://example.org/demo"

  def setup
    @tmp = Dir.mktmpdir
    @src = File.join(@tmp, "site")
    FileUtils.mkdir_p(File.join(@src, "_data"))
    FileUtils.mkdir_p(File.join(@src, "_layouts"))
    FileUtils.mkdir_p(File.join(@src, "objects/thumbs"))
    %w[map p1 p2].each { |n| FileUtils.cp(File.join(FIXTURES, "site/objects/Page1.jpg"), File.join(@src, "objects/#{n}.jpg")) }
    FileUtils.cp(File.join(FIXTURES, "site/objects/Page1.jpg"), File.join(@src, "objects/thumbs/map_th.jpg"))
    # p1 has level 0 files (only the description is read here)
    FileUtils.mkdir_p(File.join(@src, "objects/iiif/3/p1"))
    File.write(File.join(@src, "objects/iiif/3/p1/_level0.json"), { "width" => 400, "height" => 300, "sizes" => [] }.to_json)
    File.write(File.join(@src, "_data/metadata.csv"), <<~CSV)
      objectid,parentid,title,description,rights,rightsstatement,iiif_behavior,object_location,image_thumb,manifest
      map,,Map,"A <b>campus</b> map",CC BY 4.0,https://creativecommons.org/licenses/by/4.0/,,/objects/map.jpg,/objects/thumbs/map_th.jpg,
      book,,Book,,,,paged,,,
      book_1,book,Book p. 1,,,,,/objects/p1.jpg,,
      book_x,book,Book (no image),,,,,/objects/missing.jpg,,
      book_2,book,Book p. 2,,,,,/objects/p2.jpg,,
      remote,,Remote,,,,,/objects/p1.jpg,,https://other.example.org/manifest.json
      record,,Record only,,,,,,,
    CSV
    File.write(File.join(@src, "_data/config-metadata.csv"), "field,display_name\ntitle,Title\nrights,Rights\n")
    File.write(File.join(@src, "_layouts/default.html"), "{{ content }}")
    File.write(File.join(@src, "viewer.html"), <<~HTML)
      ---
      layout: default
      ---
      {{ "map" | iiif_manifest }}|{{ "book" | iiif_manifest: 2 }}|{{ "remote" | iiif_manifest }}|{{ "book_1" | iiif_manifest }}
    HTML
    @config = { "url" => "https://example.org", "baseurl" => "/demo", "title" => "Demo site", "plugins" => [],
                "metadata" => "metadata",
                "static_iiif" => { "manifests" => {
                  "v2" => "iiif/2/%{id}/manifest.json", "language" => "en", "summary" => "description",
                  "rights" => "rightsstatement", "behavior" => "iiif_behavior", "homepage" => "items/%{objectid}.html",
                  "provider" => true, "required_statement" => %w[Rights rights], "defaults" => { "behavior" => "individuals" },
                  "metadata_skip" => %w[title description manifest]
                } } }
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def build(config = @config)
    File.write(File.join(@src, "_config.yml"), config.to_yaml)
    out = File.join(@tmp, "_site")
    Jekyll::Site.new(Jekyll.configuration("source" => @src, "destination" => out, "quiet" => true)).process
    out
  end

  def read(out, path)
    JSON.parse(File.read(File.join(out, path)))
  end

  def test_items_that_get_a_manifest
    out = build
    assert_equal %w[book map], Dir.children(File.join(out, "iiif/3")).sort # not children, external manifests or records
    assert_equal %w[book map], Dir.children(File.join(out, "iiif/2")).sort
  end

  def test_single_image_item
    h = read(build, "iiif/3/map/manifest.json")
    assert_equal "#{BASE}/iiif/3/map/manifest.json", h["id"]
    assert_equal({ "none" => ["Map"] }, h["label"])
    assert_equal({ "none" => ["A campus map"] }, h["summary"])
    assert_equal [{ "label" => { "en" => ["Rights"] }, "value" => { "none" => ["CC BY 4.0"] } }], h["metadata"]
    assert_equal({ "label" => { "en" => ["Rights"] }, "value" => { "none" => ["CC BY 4.0"] } }, h["requiredStatement"])
    assert_equal "http://creativecommons.org/licenses/by/4.0/", h["rights"]
    assert_equal ["individuals"], h["behavior"]
    assert_equal({ "id" => "#{BASE}/items/map.html", "type" => "Text", "label" => { "none" => ["Map"] }, "format" => "text/html" },
                 h["homepage"][0])
    assert_equal({ "id" => "#{BASE}/objects/thumbs/map_th.jpg", "type" => "Image", "format" => "image/jpeg", "width" => 400, "height" => 300 },
                 h["thumbnail"][0])
    provider = h["provider"][0]
    assert_equal ["#{BASE}/", { "en" => ["Demo site"] }], [provider["id"], provider["label"]]
    assert_equal 1, h["items"].size
    canvas = h["items"][0]
    assert_equal [{ "none" => ["Map"] }, 400, 300], [canvas["label"], canvas["width"], canvas["height"]]
    body = canvas["items"][0]["items"][0]["body"]
    assert_equal "#{BASE}/objects/map.jpg", body["id"] # no level 0 files: the image itself
    refute body.key?("service")
  end

  def test_compound_object
    h = read(build, "iiif/3/book/manifest.json")
    assert_equal ["paged"], h["behavior"]
    refute h.key?("thumbnail")
    assert_equal [["Book p. 1"], ["Book p. 2"]], h["items"].map { |c| c["label"]["none"] } # the child without an image is left out
    assert_equal "#{BASE}/iiif/3/book/canvas/p2", h["items"][1]["id"]
    body = h["items"][0]["items"][0]["items"][0]["body"]
    assert_equal "#{BASE}/objects/iiif/3/p1/full/max/0/default.jpg", body["id"]
    assert_equal [{ "id" => "#{BASE}/objects/iiif/3/p1", "type" => "ImageService3", "profile" => "level0" }], body["service"]
  end

  def test_annotations
    FileUtils.mkdir_p(File.join(@src, "iiif/annotations"))
    File.write(File.join(@src, "iiif/annotations/book.csv"), <<~CSV)
      canvas,xywh,text,motivation
      2,"10, 20, 30, 40",Person,
      2,,Whole page,tagging
      9,,No such canvas,
      1,,,
    CSV
    out = build
    h = read(out, "iiif/3/book/manifest.json")
    refute h["items"][0].key?("annotations")
    page = h["items"][1]["annotations"]
    canvas = "#{BASE}/iiif/3/book/canvas/p2"
    assert_equal [{ "id" => "#{canvas}/annotations", "type" => "AnnotationPage", "items" => [
      { "id" => "#{canvas}/annotation/1", "type" => "Annotation", "motivation" => "commenting",
        "body" => { "type" => "TextualBody", "value" => "Person", "format" => "text/plain" },
        "target" => "#{canvas}#xywh=10,20,30,40" },
      { "id" => "#{canvas}/annotation/2", "type" => "Annotation", "motivation" => "tagging",
        "body" => { "type" => "TextualBody", "value" => "Whole page", "format" => "text/plain" },
        "target" => canvas }
    ] }], page
    refute JSON.generate(read(out, "iiif/2/book/manifest.json")).include?("Person") # version 3 only
  end

  def test_version_2
    h = read(build, "iiif/2/map/manifest.json")
    assert_equal "#{BASE}/iiif/2/map/manifest.json", h["@id"]
    assert_equal "CC BY 4.0", h["attribution"]
    assert_equal "individuals", h["sequences"][0]["viewingHint"]
    assert_equal({ "@id" => "#{BASE}/objects/thumbs/map_th.jpg", "@type" => "dctypes:Image", "format" => "image/jpeg" }, h["thumbnail"])
  end

  def test_manifest_filter
    assert_equal "#{BASE}/iiif/3/map/manifest.json|#{BASE}/iiif/2/book/manifest.json||",
                 File.read(File.join(build, "viewer.html")).strip
  end

  def test_second_build_links_to_the_first_ones_manifests
    config = Marshal.load(Marshal.dump(@config))
    config["baseurl"] = "/demo/en"
    config["static_iiif"]["manifests"].merge!("base_url" => "/demo", "write" => false)
    out = build(config)
    refute File.exist?(File.join(out, "iiif"))
    assert_equal "#{BASE}/iiif/3/map/manifest.json|#{BASE}/iiif/2/book/manifest.json||",
                 File.read(File.join(out, "viewer.html")).strip
  end

  def test_table_of_manifests_outlives_garbage_collection
    config = Marshal.load(Marshal.dump(@config))
    config["static_iiif"]["manifests"]["write"] = false
    File.write(File.join(@src, "_config.yml"), config.to_yaml)
    site = Jekyll::Site.new(Jekyll.configuration("source" => @src, "destination" => File.join(@tmp, "_site"), "quiet" => true))
    site.reset
    site.read
    site.generate
    GC.start
    assert_equal "#{BASE}/iiif/3/map/manifest.json", StaticIIIF::Jekyll.manifests(site)[3]["map"]
  end

  def test_turned_off
    config = Marshal.load(Marshal.dump(@config))
    config["static_iiif"]["manifests"]["local_images"] = false
    refute File.exist?(File.join(build(config), "iiif"))
  end
end
