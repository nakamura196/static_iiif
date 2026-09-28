# frozen_string_literal: true

require "test_helper"

class TestImageSize < Minitest::Test
  def test_baseline_jpeg_with_exif
    assert_equal [13, 7], StaticIIIF::ImageSize.read(File.join(FIXTURES, "baseline.jpg"))
  end

  def test_progressive_jpeg
    assert_equal [13, 7], StaticIIIF::ImageSize.read(File.join(FIXTURES, "progressive.jpg"))
  end

  def test_png
    assert_equal [13, 7], StaticIIIF::ImageSize.read(File.join(FIXTURES, "image.png"))
  end

  def test_not_an_image
    assert_nil StaticIIIF::ImageSize.read(__FILE__)
  end

  def test_missing_file
    assert_nil StaticIIIF::ImageSize.read(File.join(FIXTURES, "nope.jpg"))
  end

  def test_truncated_jpeg
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cut.jpg")
      File.binwrite(path, File.binread(File.join(FIXTURES, "baseline.jpg"))[0, 30])
      assert_nil StaticIIIF::ImageSize.read(path)
    end
  end
end
