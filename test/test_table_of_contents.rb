# frozen_string_literal: true

require "test_helper"

class TestTableOfContents < Minitest::Test
  def parse(text, n = 20)
    StaticIIIF::TableOfContents.parse(text, n)
  end

  def test_four_columns
    ranges = parse("r1, 序, 1-3\nr2, 本文, 4-6;9, r3\nr3, 第一章, 4")
    assert_equal({ id: "r1", label: "序", canvases: [1, 2, 3], ranges: [] }, ranges[0])
    assert_equal({ id: "r2", label: "本文", canvases: [4, 5, 6, 9], ranges: ["r3"] }, ranges[1])
    assert_equal [4], ranges[2][:canvases]
  end

  def test_parent_with_children_in_the_third_column
    ranges = parse("top, Book, r1;r2\nr1, A, 1-2\nr2, B, 3")
    assert_equal %w[r1 r2], ranges[0][:ranges]
    assert_empty ranges[0][:canvases]
    assert ranges[0][:top]
    refute ranges[1].key?(:top)
  end

  def test_no_top_flag_with_several_roots_or_own_pages
    refute parse("a, A, 1\nb, B, 2").any? { |r| r[:top] }
    refute parse("a, A, 1, b\nb, B, 2").any? { |r| r[:top] }
  end

  def test_pages_outside_the_canvases_and_reversed_runs
    assert_equal [1, 2, 3], parse("a, A, 0;3-1;2;99", 5)[0][:canvases]
  end

  def test_ignores_dashes_blank_lines_and_short_lines
    ranges = parse("\n  \nbroken line\na, A, -, \n　b, B　, 2　\n")
    assert_equal %w[a b], ranges.map { |r| r[:id] }
    assert_equal "B", ranges[1][:label]
    assert_equal [2], ranges[1][:canvases]
  end

  def test_id_that_looks_like_a_page_number_is_a_range
    ranges = parse("1, One, 2\n2, Two, 3\nr, Top, 1")
    assert_equal ["1"], ranges[2][:ranges]
    assert_empty ranges[2][:canvases]
  end

  def test_self_reference_and_empty_text
    assert_empty parse("a, A, a;1", 3)[0][:ranges]
    assert_equal [], parse("")
    assert_equal [], parse(nil)
  end
end
