# frozen_string_literal: true

module StaticIIIF
  # Reads the table of contents text that Omeka S (the IiifServer module) keeps in
  # dcterms:tableOfContents, one range per line:
  #
  #   r1, Preface, 1-3
  #   r2, Chapter 1, 4-9;12, r3
  #   r3, Section 1.1, 4-5
  #
  # Columns are range id, label, pages and, optionally, child range ids. Pages
  # are canvas numbers counted from 1 ("5", or "5-7" for a run), several
  # separated by ";". A column may also hold child range ids, so the line
  # `r2, Chapter 1, r3` works too (Omeka itself skips such parent ranges). A
  # "-" or an empty column is ignored. Labels cannot contain commas.
  #
  # Returns the ranges in file order, for Manifest#structures:
  #
  #   [{ id: "r2", label: "Chapter 1", canvases: [4, 5, 6, 7, 8, 9, 12], ranges: ["r3"] }, ...]
  #
  # The one top-level range, when there is exactly one and it only holds other
  # ranges, also has `top: true` (written as viewingHint "top" in version 2).
  module TableOfContents
    LINE_BREAK = /\r\n|[\n\r\v\f\x1c-\x1e\u0085  ]/
    PAGES = /\A(\d+)(?:[[:space:]]*-[[:space:]]*(\d+))?\z/

    module_function

    # Python-style strip: also removes full-width spaces, which Ruby's strip keeps.
    def clean(text)
      text.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    end

    def parse(text, num_canvases)
      lines = text.to_s.split(LINE_BREAK).map { |l| clean(l) }.reject(&:empty?)
      entries = lines.filter_map do |line|
        parts = line.split(",", -1).map { |p| clean(p) }
        [parts[0], parts[1], parts[2..]] if parts.size >= 3
      end
      return [] if entries.empty?

      defined_ids = entries.to_h { |rid, _, _| [rid, true] }
      referenced = {}
      ranges = entries.map do |rid, label, rest|
        canvases = []
        children = []
        rest.each do |column|
          column.split(";", -1).each do |token|
            tok = clean(token)
            next if tok.empty? || tok == "-"

            if (m = PAGES.match(tok)) && !defined_ids[tok]
              from = m[1].to_i
              to = m[2] ? m[2].to_i : from
              from, to = to, from if from > to
              (from..to).each { |n| canvases << n if n >= 1 && n <= num_canvases && !canvases.include?(n) }
            elsif defined_ids[tok] && tok != rid && !children.include?(tok)
              children << tok
              referenced[tok] = true
            end
          end
        end
        { id: rid, label: label, canvases: canvases, ranges: children }
      end

      roots = ranges.reject { |r| referenced[r[:id]] }
      roots.first[:top] = true if roots.size == 1 && roots.first[:canvases].empty? && !roots.first[:ranges].empty?
      ranges
    end
  end
end
