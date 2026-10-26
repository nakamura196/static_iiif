# frozen_string_literal: true

require "test_helper"
require "static_iiif/jekyll"

class TestServices < Minitest::Test
  S = StaticIIIF::Services
  A = "https://images.example.org/iiif/2/a"
  B = "https://images.example.org/iiif/3/b"

  INFO = {
    "#{A}/info.json" => { "@context" => "http://iiif.io/api/image/2/context.json", "@id" => "http://internal:8182/iiif/2/a",
                          "width" => 5732, "height" => 4046,
                          "profile" => ["http://iiif.io/api/image/2/level2.json", { "formats" => ["jpg"] }] },
    "#{B}/info.json" => { "@context" => "http://iiif.io/api/image/3/context.json", "id" => B, "type" => "ImageService3",
                          "width" => 1000, "height" => 800, "profile" => "level1" }
  }.freeze

  def setup
    @tmp = Dir.mktmpdir
    @out = File.join(@tmp, "_iiif/services.csv")
    @calls = []
    @fetch = lambda do |url|
      @calls << url
      INFO.fetch(url) { raise "HTTP 404" }
    end
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_service_of
    assert_equal A, S.service_of("#{A}/info.json")
    assert_nil S.service_of("#{A}/full/max/0/default.jpg")
    assert_nil S.service_of("objects/info.json")
  end

  def test_parse_info_v2_and_v3
    assert_equal({ "width" => 5732, "height" => 4046, "profile" => "level2", "version" => 2, "id" => "http://internal:8182/iiif/2/a" },
                 S.parse_info(INFO["#{A}/info.json"]))
    assert_equal 3, S.parse_info(INFO["#{B}/info.json"])["version"]
    assert_equal "level1", S.parse_info(INFO["#{B}/info.json"])["profile"]
  end

  def test_update_reads_each_once_and_writes_only_on_change
    urls = ["#{A}/info.json", "#{B}/info.json"]
    r = S.update(urls, @out, fetch: @fetch)
    assert_equal [2, 0, true], [r[:fetched], r[:reused], r[:written]]
    assert_equal [["#{A}/info.json", "http://internal:8182/iiif/2/a"]], r[:renamed] # the given URL is kept
    assert_equal({ "width" => 5732, "height" => 4046, "profile" => "level2", "version" => 2 }, S.read(@out)[A])

    r = S.update(urls, @out, fetch: @fetch)
    assert_equal [0, 2, false], [r[:fetched], r[:reused], r[:written]]
    assert_equal 2, @calls.size

    S.update(urls, @out, fetch: @fetch, refresh: true)
    assert_equal 4, @calls.size
  end

  def test_failures_are_reported_and_left_out
    r = S.update(["#{A}/info.json", "https://images.example.org/iiif/2/gone/info.json"], @out, fetch: @fetch)
    assert_equal [["https://images.example.org/iiif/2/gone/info.json", "HTTP 404"]], r[:failed]
    assert_equal [A], S.read(@out).keys
  end

  def test_manifest_from_info_json_rows
    S.update(["#{A}/info.json", "#{B}/info.json"], @out, fetch: @fetch)
    rows = [{ "objectid" => "doc", "title" => "Doc" },
            { "objectid" => "p1", "parentid" => "doc", "title" => "1", "object_location" => "#{A}/info.json" },
            { "objectid" => "p2", "parentid" => "doc", "title" => "2", "object_location" => "#{B}/info.json" }]
    dm = StaticIIIF::DataManifests.new({}, base_url: "https://example.org", rows: rows, services: S.read(@out))
    assert dm.manifest?(rows[0])
    h = dm.manifest(rows[0]).to_h(version: 3)
    bodies = h["items"].map { |c| c["items"][0]["items"][0]["body"] }
    assert_equal ["#{A}/full/full/0/default.jpg", "#{B}/full/max/0/default.jpg"], bodies.map { |b| b["id"] }
    assert_equal [5732, 1000], bodies.map { |b| b["width"] }
    assert_equal({ "@id" => A, "@type" => "ImageService2", "profile" => "http://iiif.io/api/image/2/level2.json" },
                 bodies[0]["service"][0].slice("@id", "@type", "profile"))
  end

  def test_no_manifest_while_a_size_is_unknown
    S.update(["#{A}/info.json"], @out, fetch: @fetch)
    rows = [{ "objectid" => "doc" },
            { "objectid" => "p1", "parentid" => "doc", "object_location" => "#{A}/info.json" },
            { "objectid" => "p2", "parentid" => "doc", "object_location" => "#{B}/info.json" }]
    dm = StaticIIIF::DataManifests.new({}, rows: rows, services: S.read(@out))
    refute dm.manifest?(rows[0])
    assert_equal({ "doc" => ["#{B}/info.json"] }, dm.missing)
  end

  Site = Struct.new(:config, :data, :source)

  def test_jekyll_rewrites_rows_for_the_rest_of_collectionbuilder
    S.update(["#{A}/info.json", "#{B}/info.json"], @out, fetch: @fetch)
    rows = [{ "objectid" => "a", "object_location" => "#{A}/info.json" },
            { "objectid" => "b", "object_location" => "#{B}/info.json", "image_thumb" => "own_thumb.jpg" },
            { "objectid" => "c", "object_location" => "https://images.example.org/iiif/2/c/info.json" },
            { "objectid" => "d", "object_location" => "/objects/d.jpg" }]
    site = Site.new({ "metadata" => "items" }, { "items" => rows }, @tmp)
    StaticIIIF::Jekyll.use_info_json(site)

    assert_equal "#{A}/full/full/0/default.jpg", rows[0]["object_location"]
    assert_equal "#{A}/info.json", rows[0]["static_iiif_info"]
    assert_equal "#{A}/full/800,/0/default.jpg", rows[0]["image_small"]
    assert_equal "#{A}/full/400,/0/default.jpg", rows[0]["image_thumb"]
    assert_equal "#{B}/full/max/0/default.jpg", rows[1]["object_location"]
    assert_equal "own_thumb.jpg", rows[1]["image_thumb"]
    assert_equal "https://images.example.org/iiif/2/c/full/full/0/default.jpg", rows[2]["object_location"] # not read yet: version 2 assumed
    assert_equal "/objects/d.jpg", rows[3]["object_location"]

    dm = StaticIIIF::DataManifests.new({}, rows: rows, services: S.read(@out))
    assert_equal A, dm.manifest(rows[0]).to_h(version: 3)["items"][0]["items"][0]["items"][0]["body"]["service"][0]["@id"]
    refute dm.manifest?(rows[2])
  end
end
