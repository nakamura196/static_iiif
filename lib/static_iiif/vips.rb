# frozen_string_literal: true

require "open3"

module StaticIIIF
  class Error < StandardError; end

  # Thin wrapper around the libvips command-line tools (vips, vipsheader).
  # Only image generation needs them; reading sizes and writing JSON do not.
  module Vips
    module_function

    def available?
      run("vips", "--version")
      true
    rescue Error
      false
    end

    def run(*cmd)
      out, status = Open3.capture2e(*cmd)
      raise Error, "#{cmd.first} failed: #{out.strip}" unless status.success?

      out
    rescue SystemCallError => e
      raise Error, "#{cmd.first} is not available (#{e.message}). Install libvips, " \
                   "e.g. `brew install vips` or `apt-get install libvips-tools`."
    end

    def size(path)
      [run("vipsheader", "-f", "width", path).to_i, run("vipsheader", "-f", "height", path).to_i]
    end
  end
end
