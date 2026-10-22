# frozen_string_literal: true

require "test_helper"
require "json"

class TestManifest < Minitest::Test
  def build
    m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/3/book/manifest.json", label: "本", language: "ja")
    m.summary = "説明"
    m.metadata << ["作者", "不明"]
    m.rights = "https://creativecommons.org/licenses/by/4.0/"
    m.required_statement = ["利用条件", "CC BY 4.0"]
    m.homepage = "https://example.org/items/book.html"
    m.provider = ["Example", "https://example.org/"]
    m.add_canvas(label: "1", image: { "id" => "https://example.org/p1.jpg", "width" => 400, "height" => 300 })
    m.add_canvas(image: { "id" => "https://example.org/iiif/3/p2/full/max/0/default.jpg", "width" => 900,
                          "height" => 600, "format" => "image/jpeg", "service" => "https://example.org/iiif/3/p2" },
                 thumbnail: "https://example.org/p2_th.jpg")
    m.to_h
  end

  def test_structure
    h = build
    assert_equal "Manifest", h["type"]
    assert_equal({ "ja" => ["本"] }, h["label"])
    assert_equal [{ "label" => { "ja" => ["作者"] }, "value" => { "none" => ["不明"] } }], h["metadata"]
    assert_equal "http://creativecommons.org/licenses/by/4.0/", h["rights"]
    assert_equal({ "label" => { "ja" => ["利用条件"] }, "value" => { "none" => ["CC BY 4.0"] } }, h["requiredStatement"])
    assert_equal({ "ja" => ["本"] }, h["homepage"][0]["label"]) # the manifest's label, not the statement's
    assert_equal 2, h["items"].size
  end

  def test_canvases
    c1, c2 = build["items"]
    assert_equal "https://example.org/iiif/3/book/canvas/p1", c1["id"]
    anno = c1["items"][0]["items"][0]
    assert_equal c1["id"], anno["target"]
    assert_equal "painting", anno["motivation"]
    refute anno["body"].key?("service")
    assert_equal({ "none" => ["2"] }, c2["label"])
    assert_equal [{ "id" => "https://example.org/iiif/3/p2", "type" => "ImageService3", "profile" => "level0" }],
                 c2["items"][0]["items"][0]["body"]["service"]
  end

  def test_rights_only_for_known_uris
    m = StaticIIIF::Manifest.new(id: "https://example.org/m.json", label: "x")
    m.rights = "All rights reserved"
    refute m.to_h.key?("rights")
    assert_equal({ "none" => ["x"] }, m.to_h["label"])
  end

  def test_image_helper_without_level0
    img = StaticIIIF.image(File.join(FIXTURES, "image.png"), url: "https://example.org/image.png")
    assert_equal({ "id" => "https://example.org/image.png", "width" => 13, "height" => 7, "format" => "image/png" }, img)
    assert_nil StaticIIIF.image(File.join(FIXTURES, "nope.jpg"), url: "x")
  end

  def test_version_2
    m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/2/book/manifest.json", label: "本", language: "ja")
    m.metadata << ["作者", "不明"]
    m.rights = "https://creativecommons.org/licenses/by/4.0/"
    m.required_statement = ["利用条件", "CC BY 4.0"]
    m.homepage = "https://example.org/items/book.html"
    m.provider = ["Example", "https://example.org/"]
    m.add_canvas(label: "1", image: { "id" => "https://example.org/iiif/2/p1/full/full/0/default.jpg", "width" => 900,
                                      "height" => 600, "service" => "https://example.org/iiif/2/p1" })
    h = m.to_h(version: 2)
    assert_equal "http://iiif.io/api/presentation/2/context.json", h["@context"]
    assert_equal "sc:Manifest", h["@type"]
    assert_equal "本", h["label"]
    assert_equal [{ "label" => "作者", "value" => "不明" }], h["metadata"]
    assert_equal "CC BY 4.0", h["attribution"]
    assert_equal "https://creativecommons.org/licenses/by/4.0/", h["license"]
    assert_equal({ "@id" => "https://example.org/items/book.html", "format" => "text/html" }, h["related"])
    refute h.key?("provider")
    canvas = h["sequences"][0]["canvases"][0]
    assert_equal "https://example.org/iiif/2/book/canvas/p1", canvas["@id"]
    anno = canvas["images"][0]
    assert_equal ["sc:painting", canvas["@id"]], [anno["motivation"], anno["on"]]
    assert_equal({ "@context" => "http://iiif.io/api/image/2/context.json", "@id" => "https://example.org/iiif/2/p1",
                   "profile" => "http://iiif.io/api/image/2/level0.json" }, anno["resource"]["service"])
  end

  def test_image_helper_version_2
    dir = Dir.mktmpdir
    File.write(File.join(dir, StaticIIIF::Level0::META_FILE), '{"width": 900, "height": 600, "sizes": []}')
    img = StaticIIIF.image(nil, level0_dir: dir, service_url: "https://example.org/iiif/2/p1/", version: 2)
    assert_equal "https://example.org/iiif/2/p1/full/full/0/default.jpg", img["id"]
    assert_equal "https://example.org/iiif/2/p1", img["service"]
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_image_info_v2
    info = StaticIIIF::ImageInfo.v2({ "width" => 900, "height" => 600, "sizes" => [{ "width" => 900, "height" => 600 }],
                                      "tiles" => [{ "width" => 256, "scaleFactors" => [1, 2] }] }, "https://example.org/iiif/2/p1/")
    assert_equal "https://example.org/iiif/2/p1", info["@id"]
    assert_equal ["http://iiif.io/api/image/2/level0.json"], info["profile"]
    assert_equal [{ "width" => 256, "scaleFactors" => [1, 2] }], info["tiles"]
    refute info.key?("type")
  end

  def test_behavior
    m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/3/book/manifest.json", label: "x")
    m.add_canvas(image: { "id" => "https://example.org/p1.jpg", "width" => 4, "height" => 3 })
    refute m.to_h.key?("behavior")
    m.behavior = "paged"
    assert_equal ["paged"], m.to_h["behavior"]
    assert_equal "paged", m.to_h(version: 2)["sequences"][0]["viewingHint"]
    refute m.to_h(version: 2).key?("viewingHint")
    m.behavior = "two-up" # not a IIIF value: left out
    refute m.to_h.key?("behavior")
    refute m.to_h(version: 2)["sequences"][0].key?("viewingHint")
  end

  SERVICE = "https://img.example.org/iiif/book/001.tif"

  def external_manifest(id, **image_options)
    m = StaticIIIF::Manifest.new(id: id, label: "本")
    m.add_canvas(label: "1", image: StaticIIIF.external_image(SERVICE, width: 400, height: 300, **image_options),
                 thumbnail: StaticIIIF.thumbnail_url(SERVICE))
    m
  end

  def test_external_image_helper
    img = StaticIIIF.external_image("#{SERVICE}/", width: "400", height: 300)
    assert_equal({ "id" => "#{SERVICE}/full/full/0/default.jpg", "width" => 400, "height" => 300, "format" => "image/jpeg",
                   "service" => SERVICE, "service_version" => 2, "profile" => "level1" }, img)
    img3 = StaticIIIF.external_image(SERVICE, width: 4, height: 3, version: 3, profile: "level2")
    assert_equal "#{SERVICE}/full/max/0/default.jpg", img3["id"]
    assert_equal [3, "level2"], img3.values_at("service_version", "profile")
    assert_equal "#{SERVICE}/full/200,/0/default.jpg", StaticIIIF.thumbnail_url(SERVICE)
    assert_equal "#{SERVICE}/full/400,/0/default.jpg", StaticIIIF.thumbnail_url("#{SERVICE}/", 400)
  end

  def test_external_service_image_api_2_in_version_3
    canvas = external_manifest("https://example.org/iiif/3/book/manifest.json").to_h["items"][0]
    assert_equal [{ "id" => "#{SERVICE}/full/200,/0/default.jpg", "type" => "Image", "format" => "image/jpeg" }], canvas["thumbnail"]
    assert_equal [{ "@context" => "http://iiif.io/api/image/2/context.json", "@id" => SERVICE, "@type" => "ImageService2",
                    "profile" => "http://iiif.io/api/image/2/level1.json" }], canvas["items"][0]["items"][0]["body"]["service"]
  end

  def test_external_service_image_api_3_in_version_3
    m = external_manifest("https://example.org/iiif/3/book/manifest.json", version: 3, profile: "http://iiif.io/api/image/3/level1.json")
    service = m.to_h["items"][0]["items"][0]["items"][0]["body"]["service"]
    assert_equal [{ "id" => SERVICE, "type" => "ImageService3", "profile" => "level1" }], service
  end

  def test_external_service_in_version_2
    canvas = external_manifest("https://example.org/iiif/2/book/manifest").to_h(version: 2)["sequences"][0]["canvases"][0]
    assert_equal({ "@id" => "#{SERVICE}/full/200,/0/default.jpg", "@type" => "dctypes:Image", "format" => "image/jpeg" }, canvas["thumbnail"])
    assert_equal({ "@context" => "http://iiif.io/api/image/2/context.json", "@id" => SERVICE,
                   "profile" => "http://iiif.io/api/image/2/level1.json" }, canvas["images"][0]["resource"]["service"])
    m = external_manifest("https://example.org/iiif/2/book/manifest", version: 3, profile: "level0")
    service = m.to_h(version: 2)["sequences"][0]["canvases"][0]["images"][0]["resource"]["service"]
    assert_equal({ "@context" => "http://iiif.io/api/image/3/context.json", "@id" => SERVICE, "profile" => "level0" }, service)
  end

  def structures
    [{ id: "r1", label: "Book", canvases: [], ranges: %w[r2 r3], top: true },
     { id: "r2", label: "Part 1", canvases: [1, 2], ranges: [] },
     { id: "r3", label: "Part 2", canvases: [3], ranges: ["r4"] },
     { id: "r4", label: "Section", canvases: [3], ranges: [] }]
  end

  def with_structures(id)
    m = StaticIIIF::Manifest.new(id: id, label: "本")
    3.times { |i| m.add_canvas(image: { "id" => "https://example.org/p#{i}.jpg", "width" => 4, "height" => 3 }) }
    m.structures = structures
    m
  end

  def test_structures_version_3_are_nested
    base = "https://example.org/iiif/3/book"
    top = with_structures("#{base}/manifest.json").to_h["structures"]
    assert_equal 1, top.size
    assert_equal({ "id" => "#{base}/range/r1", "type" => "Range", "label" => { "none" => ["Book"] } }, top[0].reject { |k, _| k == "items" })
    part1, part2 = top[0]["items"]
    assert_equal [{ "id" => "#{base}/canvas/p1", "type" => "Canvas" }, { "id" => "#{base}/canvas/p2", "type" => "Canvas" }], part1["items"]
    assert_equal "#{base}/range/r3", part2["id"]
    assert_equal ["Canvas", "Range"], part2["items"].map { |i| i["type"] }
    assert_equal "#{base}/range/r4", part2["items"][1]["id"]
  end

  def test_structures_version_2_are_flat
    base = "https://example.org/iiif/2/book"
    list = with_structures("#{base}/manifest").to_h(version: 2)["structures"]
    assert_equal %w[r1 r2 r3 r4].map { |r| "#{base}/range/#{r}" }, list.map { |r| r["@id"] }
    assert_equal({ "@id" => "#{base}/range/r1", "@type" => "sc:Range", "label" => "Book", "viewingHint" => "top",
                   "ranges" => ["#{base}/range/r2", "#{base}/range/r3"] }, list[0])
    assert_equal ["#{base}/canvas/p1", "#{base}/canvas/p2"], list[1]["canvases"]
    refute list[1].key?("viewingHint")
    refute list[1].key?("ranges")
  end

  def test_structures_nested_deeper_than_the_json_default
    m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/3/book/manifest.json", label: "x")
    m.add_canvas(image: { "id" => "https://example.org/p.jpg", "width" => 4, "height" => 3 })
    m.structures = (1..150).map { |i| { id: "r#{i}", label: "R#{i}", canvases: i == 150 ? [1] : [], ranges: i == 150 ? [] : ["r#{i + 1}"] } }
    assert_equal 1, m.to_h["structures"].size
    assert_equal 150, m.to_h(version: 2)["structures"].size
    assert JSON.generate(m.to_h, max_nesting: false).include?("range/r150")
  end

  def test_no_structures_by_default
    m = StaticIIIF::Manifest.new(id: "https://example.org/m.json", label: "x")
    refute m.to_h.key?("structures")
    refute m.to_h(version: 2).key?("structures")
  end
end
