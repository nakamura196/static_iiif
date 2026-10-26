# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "net/http"
require "uri"
require_relative "version"

module StaticIIIF
  # Images on another IIIF server, given by their info.json URL in the metadata CSV
  # (`object_location`). A manifest needs each image's size, so the sizes are read
  # from the info.json files once (`static-iiif sizes`) and kept in one CSV file
  # (default _iiif/services.csv) that the build reads:
  #
  #   service,width,height,profile,version
  #   https://images.example.org/iiif/2/doc001_0001,5732,4046,level2,2
  #
  # `service` is the URL as written in the metadata, without /info.json; it wins over
  # the id the info.json gives for itself (servers often report http:// or an
  # internal host name).
  module Services
    COLUMNS = %w[service width height profile version].freeze
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
    def full_url(service, version)
      "#{service}/full/#{version.to_i == 3 ? 'max' : 'full'}/0/default.jpg"
    end

    # { service => { "width", "height", "profile", "version" } } (empty if there is no file)
    def read(path)
      return {} unless File.file?(path)

      CSV.foreach(path, headers: true, encoding: "UTF-8").each_with_object({}) do |r, out|
        service = r["service"].to_s.strip
        next if service.empty? || r["width"].to_i <= 0 || r["height"].to_i <= 0

        out[service] = { "width" => r["width"].to_i, "height" => r["height"].to_i,
                         "profile" => r["profile"].to_s.strip, "version" => r["version"].to_i == 3 ? 3 : 2 }
      end
    end

    def write(path, table)
      content = CSV.generate do |csv|
        csv << COLUMNS
        table.each { |service, s| csv << [service, s["width"], s["height"], s["profile"], s["version"]] }
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
      { "width" => info["width"].to_i, "height" => info["height"].to_i, "profile" => profile,
        "version" => version, "id" => (info["id"] || info["@id"]).to_s }
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
      todo = urls.reject { |u| !refresh && table.key?(service_of(u)) }
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
        table[service] = info.slice("width", "height", "profile", "version")
        result[:fetched] += 1
      end
      result[:written] = write(path, table)
      result
    end
  end
end
