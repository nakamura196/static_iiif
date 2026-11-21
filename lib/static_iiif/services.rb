# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "uri"
require_relative "version"

module StaticIIIF
  # Images on another IIIF server, given by their info.json URL in the metadata CSV
  # (`object_location`). A manifest needs each image's size, so the sizes are read
  # from the info.json files once (`static-iiif sizes`) and kept in one CSV file
  # (default _iiif/services.csv) that the build reads:
  #
  #   service,width,height,profile,version,sizes,max_width,max_height,max_area
  #   https://images.example.org/iiif/2/doc001_0001,5732,4046,level2,2,358x253;716x506,,,
  #
  # `sizes` (the info.json's `sizes`, as WxH separated by ";") and the limits
  # (maxWidth, maxHeight, maxArea) decide which image URLs the server can answer:
  # see `sized_url` and `full_url`. A level 0 server has only its listed sizes.
  #
  # `service` is the URL as written in the metadata, without /info.json; it wins over
  # the id the info.json gives for itself (servers often report http:// or an
  # internal host name).
  module Services
    COLUMNS = %w[service width height profile version sizes max_width max_height max_area].freeze
    EXTRA = %w[sizes max_width max_height max_area].freeze
    INFO = %r{/info\.json\z}i
    FULL = %r{/full/(?:max|full)/0/default\.jpg\z}

    module_function

    # The service URL of an info.json URL, or nil if the value is not one.
    def service_of(url)
      url = url.to_s.strip
      return nil unless url.match?(%r{\Ahttps?://}i) && url.match?(INFO)

      url.sub(INFO, "")
    end

    # The whole image of a service: full/max for version 3, full/full for version 2.
    # With the service's entry from `read` (`info`), an image the server can give:
    # - level 0 that lists its sizes without the full one: the largest listed size;
    # - version 2 with limits the image is over: the largest size within them
    #   (version 3's `max` already means "as large as allowed").
    def full_url(service, version, info = nil)
      version = (info && info["version"]) || version
      if info && level0?(info) && !info["sizes"].to_a.empty? && info["sizes"].none? { |w, _| w == info["width"] }
        return image_url(service, info["sizes"].max_by(&:first), version, listed: true)
      end
      if info && version.to_i == 2 && !level0?(info) && (w = limited_width(info, info["width"])) < info["width"]
        return image_url(service, [w, nil], version)
      end

      "#{service}/full/#{version.to_i == 3 ? 'max' : 'full'}/0/default.jpg"
    end

    # The URL of an image about `width` pixels wide that the service can give, from its
    # entry in `read` (`info`; without one, simply `width` pixels wide, as before):
    # - level 0: the smallest listed size at least `width` wide, else the largest;
    #   with no sizes listed, the whole image;
    # - otherwise: a listed size from `width` to twice it (the server has it ready),
    #   else `width`, but no wider than the image (version 3 would need ^ to upscale)
    #   and within maxWidth, maxHeight and maxArea.
    # Listed sizes use the canonical form (w, for version 2, w,h for version 3), which
    # is what static level 0 files are named by.
    def sized_url(service, info, width)
      width = width.to_i
      return "#{service}/full/#{width},/0/default.jpg" unless info

      version = info["version"] || 2
      sizes = info["sizes"].to_a
      if level0?(info)
        return full_url(service, version, info) if sizes.empty?

        size = sizes.select { |w, _| w >= width }.min_by(&:first) || sizes.max_by(&:first)
        return image_url(service, size, version, listed: true)
      end
      size = sizes.select { |w, _| w >= width && w <= 2 * width }.min_by(&:first)
      size = nil if size && limited_width(info, size[0]) < size[0]
      return image_url(service, size, version, listed: true) if size

      image_url(service, [limited_width(info, [width, info["width"]].min), nil], version)
    end

    def level0?(info)
      info["profile"].to_s == "level0"
    end

    def image_url(service, size, version, listed: false)
      w, h = size
      param = listed && version.to_i == 3 && h ? "#{w},#{h}" : "#{w},"
      "#{service}/full/#{param}/0/default.jpg"
    end

    # `width`, made smaller if the server's maxWidth, maxHeight or maxArea would refuse it.
    def limited_width(info, width)
      iw = info["width"].to_f
      ih = info["height"].to_f
      w = width.to_f
      w = [w, info["max_width"].to_f].min if info["max_width"].to_i.positive?
      w = [w, info["max_height"].to_f * iw / ih].min if info["max_height"].to_i.positive? && ih.positive?
      w = [w, Math.sqrt(info["max_area"].to_f * iw / ih)].min if info["max_area"].to_i.positive? && ih.positive?
      [w.floor, 1].max
    end

    def parse_sizes(value)
      value.to_s.split(";").filter_map do |s|
        w, h = s.split("x").map(&:to_i)
        [w, h] if w.to_i.positive? && h.to_i.positive?
      end
    end

    def format_sizes(sizes)
      sizes.to_a.map { |w, h| "#{w}x#{h}" }.join(";")
    end

    # { service => { "width", "height", "profile", "version" } } (empty if there is no file)
    def read(path)
      return {} unless File.file?(path)

      table = CSV.read(path, headers: true, encoding: "UTF-8")
      has_sizes = table.headers.include?("sizes") # files from 0.5.3 and before have no sizes
      table.each_with_object({}) do |r, out|
        service = r["service"].to_s.strip
        next if service.empty? || r["width"].to_i <= 0 || r["height"].to_i <= 0

        out[service] = { "width" => r["width"].to_i, "height" => r["height"].to_i,
                         "profile" => r["profile"].to_s.strip, "version" => r["version"].to_i == 3 ? 3 : 2,
                         "sizes" => has_sizes ? parse_sizes(r["sizes"]) : nil }
        %w[max_width max_height max_area].each { |k| out[service][k] = r[k].to_i if r[k].to_i.positive? }
      end
    end

    def write(path, table)
      content = CSV.generate do |csv|
        csv << COLUMNS
        table.each do |service, s|
          csv << [service, s["width"], s["height"], s["profile"], s["version"], format_sizes(s["sizes"]),
                  s["max_width"], s["max_height"], s["max_area"]]
        end
      end
      return false if File.file?(path) && File.read(path, encoding: "UTF-8") == content

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      true
    end

    # Size, version and profile from a parsed info.json (Image API 2 or 3).
    def parse_info(info)
      context = Array(info["@context"]).join(" ")
      version = context.include?("/image/3/") || info["type"] == "ImageService3" ? 3 : 2
      profile = Array(info["profile"]).find { |p| p.is_a?(String) }.to_s
      profile = profile[/level[012]/] || profile
      # version 3 has the limits at the top; version 2 in the profile's description
      limits = [info, *Array(info["profile"]).grep(Hash)]
      limit = ->(key) { limits.map { |h| h[key].to_i }.find(&:positive?) }
      sizes = Array(info["sizes"]).filter_map do |s|
        [s["width"].to_i, s["height"].to_i] if s.is_a?(Hash) && s["width"].to_i.positive? && s["height"].to_i.positive?
      end
      { "width" => info["width"].to_i, "height" => info["height"].to_i, "profile" => profile,
        "version" => version, "sizes" => sizes.uniq.sort, "max_width" => limit.call("maxWidth"),
        "max_height" => limit.call("maxHeight"), "max_area" => limit.call("maxArea"),
        "id" => (info["id"] || info["@id"]).to_s }.compact
    end

    # The info.json URLs in a column of metadata CSV files, each once, in order.
    def urls_from_csv(paths, column: "object_location")
      Array(paths).flat_map do |path|
        CSV.foreach(path, headers: true, encoding: "UTF-8").filter_map { |r| r[column].to_s.strip if service_of(r[column]) }
      end.uniq
    end

    # GET an info.json and parse it: a timeout, up to 3 tries with a pause, at most 3 redirects.
    def fetch(url, tries: 3, pause: 2, timeout: 30)
      attempt = 0
      begin
        attempt += 1
        JSON.parse(get(URI(url), timeout))
      rescue StandardError
        raise if attempt >= tries

        sleep(pause * attempt)
        retry
      end
    end

    def get(uri, timeout, redirects = 3)
      require "net/http"
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "static_iiif/#{VERSION}", "Accept" => "application/json"))
      end
      case res
      when Net::HTTPSuccess then res.body
      when Net::HTTPRedirection
        raise "too many redirects" if redirects <= 0

        get(URI.join(uri.to_s, res["location"]), timeout, redirects - 1)
      else raise "HTTP #{res.code}"
      end
    end

    # Read the size of every info.json URL not yet in the file (all of them with
    # refresh: true) and write the file if anything changed. Rows for images no longer
    # in the metadata are kept. `fetch` is a callable (url → parsed info.json), so tests
    # need no network.
    #
    # Returns { fetched:, reused:, failed: [[url, message]], renamed: [[url, id]], written: }
    def update(urls, path, fetch: method(:fetch), jobs: 4, refresh: false)
      table = read(path)
      # rows written before sizes were kept are read again
      todo = urls.reject { |u| !refresh && table.key?(service_of(u)) && !table[service_of(u)]["sizes"].nil? }
      result = { fetched: 0, reused: urls.size - todo.size, failed: [], renamed: [], written: false }
      queue = Queue.new
      todo.each { |u| queue << u }
      found = {}
      lock = Mutex.new
      Array.new([jobs.to_i, 1].max) do
        Thread.new do
          while (url = (queue.pop(true) rescue nil))
            outcome = begin
              [parse_info(fetch.call(url)), nil]
            rescue StandardError => e
              [nil, e.message]
            end
            lock.synchronize { found[url] = outcome }
          end
        end
      end.each(&:join)
      todo.each do |url|
        info, error = found[url]
        service = service_of(url)
        if info.nil? || info["width"] <= 0 || info["height"] <= 0
          result[:failed] << [url, error || "no width or height"]
          next
        end
        result[:renamed] << [url, info["id"]] unless info["id"].empty? || info["id"].chomp("/") == service
        table[service] = info.slice("width", "height", "profile", "version", *EXTRA)
        result[:fetched] += 1
      end
      result[:written] = write(path, table)
      result
    end
  end
end
