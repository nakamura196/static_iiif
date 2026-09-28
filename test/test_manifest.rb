# frozen_string_literal: true

require "test_helper"

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
end
