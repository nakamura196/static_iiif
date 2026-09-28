# frozen_string_literal: true

module StaticIIIF
  # Pixel size of a JPEG or PNG, read from the file header without an image
  # library. Returns [width, height], or nil for other formats and broken files.
  module ImageSize
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    # SOF0..SOF15 carry the frame size; C4 (DHT), C8 (JPG) and CC (DAC) do not
    SOF_MARKERS = ((0xC0..0xCF).to_a - [0xC4, 0xC8, 0xCC]).freeze
    # markers without a length field
    STANDALONE = ([0x01] + (0xD0..0xD8).to_a).freeze

    module_function

    def read(path)
      File.open(path, "rb") do |f|
        head = f.read(24)
        return nil if head.nil? || head.bytesize < 24
        return head.byteslice(16, 8).unpack("NN") if head.start_with?(PNG_SIGNATURE)
        return nil unless head.start_with?("\xFF\xD8".b)

        jpeg(f)
      end
    rescue SystemCallError, IOError
      nil
    end

    def jpeg(file)
      file.seek(2)
      loop do
        byte = file.read(1) or return nil
        next unless byte.ord == 0xFF

        code = file.read(1) or return nil
        code = code.ord
        next if code == 0xFF || STANDALONE.include?(code) # fill bytes / no length

        length = file.read(2)&.unpack1("n") or return nil
        if SOF_MARKERS.include?(code)
          data = file.read(5) or return nil
          height, width = data.unpack("xnn")
          return [width, height]
        end
        file.seek(length - 2, IO::SEEK_CUR)
      end
    end
  end
end
