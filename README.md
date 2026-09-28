# static_iiif

IIIF for static sites: publish local images as IIIF without an image server.

- **Image API 3, level 0**: a few fixed sizes of each image, plus tiles only
  for images larger than a threshold (4000 px on the long side by default).
  Most images cost a handful of files; large maps and scrolls get deep zoom.
- **info.json with the site's own URL**, written at build time (Jekyll) or
  with `--base-url`, so the same image files work in development and production.
- **Presentation 3 manifests**, from a small Ruby builder or from your own
  templates (a Liquid filter reads each image's size from its file header).
- **Version 2 beside version 3, if you want it**: Image API 2 folders made
  entirely of links into the version 3 ones, and Presentation 2 manifests, for
  viewers and tools that read only version 2.
- The full image is **linked, not copied**, so a repository does not hold the
  original twice.

Why: static collection sites (CollectionBuilder, Wax, plain Jekyll) mostly
either show IIIF from someone else's server, or skip IIIF altogether. The
Ruby tool that did make static IIIF, [wax_iiif](https://github.com/minicomp/wax_iiif),
writes IIIF 2.0 only, always tiles every image, and has not changed since 2023.
static_iiif writes IIIF 3 (and, optionally, 2), tiles only what needs it, and
keeps the API version in the URL (`.../iiif/3/...`, `.../iiif/2/...`, as Omeka S
IIIF Server does), because a static host cannot choose a version by content
negotiation.

Tested with Mirador 3 (uses the sizes and the tiles, in version 3 and 2) and
Universal Viewer 4 (displays the version 3 manifests; it loads the full image
rather than the level 0 service).

Requires Ruby 3.1+ and, for making images only, the libvips command-line tools
(`brew install vips`, `apt-get install libvips-tools`). libvips 8.16 leaves the
smallest tile level out of info.json (8.18 includes it); viewers then start one
level higher, which is harmless.

## Command

```sh
static-iiif generate objects objects/iiif/3 --base-url https://example.org/objects/iiif/3
```

For every image in `objects/`, writes `objects/iiif/3/<name>/` (`<name>` is the
file name without extension, lowercased):

```
full/max/0/default.jpg          the full image (a link to the original JPEG)
full/<w>,<h>/0/default.jpg      the full image by size, and each of --sizes
<x>,<y>,<w>,<h>/.../default.jpg tiles (only above --tile-threshold)
_level0.json                    what was made
info.json                       with --base-url
```

Options: `--sizes 256,1024`, `--tile-threshold 4000` (0 = never tile),
`--tile-size 512`, `--force` (images whose files are newer than their output
are redone anyway).

### Version 2

```sh
static-iiif generate objects objects/iiif/3 --v2-dir objects/iiif/2 --v2-base-url https://example.org/objects/iiif/2
```

`--v2-dir` also writes an Image API 2 folder per image. The two versions differ
only in how a size is written in the URL (`<w>,` in 2, `<w>,<h>` in 3; the full
size is `full` or `max` in 2), so every file in it is a link to the same image
in the version 3 folder or to the original. The repository gains links only;
a site builder that writes real files (Jekyll in production) does publish the
images a second time.

## Ruby

```ruby
require "static_iiif"

StaticIIIF::Level0.new(sizes: [256, 1024], tile_threshold: 4000)
                  .generate("objects/map.jpg", "objects/iiif/3/map")

m = StaticIIIF::Manifest.new(id: "https://example.org/iiif/3/map/manifest.json",
                             label: "Campus map", language: "en")
m.metadata << ["Date", "1930"]
m.rights = "http://creativecommons.org/licenses/by/4.0/"
m.add_canvas(label: "1", image: StaticIIIF.image("objects/map.jpg",
  url: "https://example.org/objects/map.jpg",                 # used without level 0 files
  level0_dir: "objects/iiif/3/map",
  service_url: "https://example.org/objects/iiif/3/map"))
File.write("iiif/3/map/manifest.json", JSON.pretty_generate(m.to_h))

# Presentation 2: a separate id, images described for version 2
StaticIIIF::Level0.derive_v2("objects/iiif/3/map", "objects/iiif/2/map")
m2 = StaticIIIF::Manifest.new(id: "https://example.org/iiif/2/map/manifest.json", label: "Campus map")
m2.add_canvas(label: "1", image: StaticIIIF.image("objects/map.jpg", url: "https://example.org/objects/map.jpg",
  level0_dir: "objects/iiif/2/map", service_url: "https://example.org/objects/iiif/2/map", version: 2))
File.write("iiif/2/map/manifest.json", JSON.pretty_generate(m2.to_h(version: 2)))
```

Presentation 2 has fewer fields: labels and values are plain strings, `rights`
and `required_statement` become `license` and `attribution`, `homepage`
becomes `related`, and `provider` is left out.

`StaticIIIF::ImageSize.read(path)` returns `[width, height]` of a JPEG or PNG
from its header, without an image library.

## Rake

```ruby
# Rakefile (or rakelib/iiif.rake)
require "static_iiif/rake_task"
StaticIIIF::RakeTask.new # rake generate_iiif; settable: input_dir, output_dir, sizes, tile_threshold, tile_size
StaticIIIF::RakeTask.new { |t| t.v2_output_dir = "objects/iiif/2" } # version 2 as well
```

## Jekyll

```ruby
# Gemfile
group :jekyll_plugins do
  gem "static_iiif"
end
```

```yaml
# _config.yml (optional; the defaults are shown)
static_iiif:
  images: objects/iiif/3
  images_v2: objects/iiif/2
```

At build time the plugin writes `info.json` into each level 0 folder under
`images` (and the version 2 one under `images_v2`), using `url` + `baseurl`. In your manifest template, the `iiif_image`
filter describes an image by its site path:

```liquid
{%- assign img = item.object_location | iiif_image -%}
"body": {
  "id": {{ img.id | jsonify }}, "type": "Image", "format": {{ img.format | jsonify }},
  "width": {{ img.width }}, "height": {{ img.height }}
  {%- if img.service %},
  "service": [ { "id": {{ img.service | jsonify }}, "type": "ImageService3", "profile": "level0" } ]
  {%- endif %}
}
```

It returns `id`, `width`, `height`, `format` and, when the image has level 0
files, `service` (and `id` then points into the service). External URLs and
files it cannot read give `nil`. For a Presentation 2 template, use
`iiif_image: 2`; `service` is then the version 2 folder, to be written as
`"service": { "@context": "http://iiif.io/api/image/2/context.json", "@id": ..., "profile": "http://iiif.io/api/image/2/level0.json" }`.

Note: in development Jekyll copies links as links (they still resolve inside
`_site`); with `JEKYLL_ENV=production` it writes the real files.

### CollectionBuilder

A working setup (manifests at `/iiif/3/<objectid>/manifest.json` and
`/iiif/2/<objectid>/manifest.json` generated with CollectionBuilder's page
generator, shown in Universal Viewer on the item page) is in
[cb-ja-demo](https://github.com/nakamura196/cb-ja-demo): see
`_layouts/item/manifest.json`, `_layouts/item/manifest-v2.json` and the
`page_gen` section of `_config.yml`.

## Status

0.2: Image API 3 level 0 and Presentation 3; optionally Image API 2 and
Presentation 2 beside them. Planned: a collection manifest, TIFF sizes without
libvips.

## Development

```sh
bundle install
bundle exec rake test   # the level 0 and Jekyll tests are skipped without libvips
```

## License

MIT
