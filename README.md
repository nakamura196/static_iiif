# static_iiif

IIIF for static sites: publish local images as IIIF without an image server.

- **Image API 3, level 0**: a few fixed sizes of each image, plus tiles only
  for images larger than a threshold (4000 px on the long side by default).
  Most images cost a handful of files; large maps and scrolls get deep zoom.
- **info.json with the site's own URL**, written at build time (Jekyll) or
  with `--base-url`, so the same image files work in development and production.
- **Presentation 3 manifests**, from a small Ruby builder or from your own
  templates (a Liquid filter reads each image's size from its file header).
- **Item manifests from the metadata CSV** with no template, the images found
  as CollectionBuilder lists them (one image, or a compound object's child rows;
  see [Item manifests from the metadata CSV](#item-manifests-from-the-metadata-csv)).
- **Manifests from data files**, for images on another IIIF server: a CSV of
  canvases and, if you have one, a table of contents per item, plus your
  metadata CSV (see [Manifests from data files](#manifests-from-data-files)).
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
m.behavior = "individuals"   # or "paged" (a book, two pages side by side), "continuous" (a scroll)
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
becomes `related`, `behavior` becomes the sequence's `viewingHint`, and
`provider` is left out.

Choose `behavior` by how the images were taken: `paged` only when each image
is one page. Collections photographed an opening at a time (common for
Japanese and other East Asian books) need `individuals`, or a viewer that
pages will show two openings side by side.

### Images on another server, and tables of contents

```ruby
service = "https://img.example.org/iiif/book/001.tif"   # an Image API 2 level 1 service
m.add_canvas(label: "1",
             image: StaticIIIF.external_image(service, width: 4000, height: 3000, version: 2, profile: "level1"),
             thumbnail: StaticIIIF.thumbnail_url(service, 200))   # <service>/full/200,/0/default.jpg
```

`external_image` needs no local file. The image `id` is `<service>/full/full/0/default.jpg` for
version 2 services and `<service>/full/max/0/default.jpg` for version 3. The manifest writes the service
as `ImageService2` (with `@context`, `@id` and the profile URI) or `ImageService3`
(`level0`, `level1`, `level2`) as the image says; without `service_version` and
`profile` it is a level 0 version 3 service, as before.

```ruby
m.structures = [
  { id: "r1", label: "Book", canvases: [], ranges: %w[r2 r3], top: true },
  { id: "r2", label: "Part 1", canvases: [1, 2], ranges: [] },   # canvas numbers from 1
  { id: "r3", label: "Part 2", canvases: [3], ranges: [] }
]
```

Version 3 gets nested `Range` objects (`<base>/range/<id>`) under `structures`; version 2 gets a flat
list of `sc:Range`, with `viewingHint: "top"` on the range marked `top: true`.

`StaticIIIF::TableOfContents.parse(text, number_of_canvases)` reads such ranges from the table of contents
text that Omeka S (IiifServer) keeps in `dcterms:tableOfContents`, one range per line:

```
r1, Preface, 1-3
r2, Chapter 1, 4-9;12, r3
r3, Section 1.1, 4-5
```

The columns are the range id, the label, the pages and, optionally, child range ids. Pages are canvas
numbers counted from 1: `5`, or a run `5-7`, several joined by `;`. A column of child ids may also
stand in the pages column (`top, Book, r1;r2`, which Omeka itself skips). `-` or an empty column is
ignored. Labels cannot contain commas. The one range that no other range holds, if it holds only
ranges, is marked `top`.

`StaticIIIF::ImageSize.read(path)` returns `[width, height]` of a JPEG or PNG
from its header, without an image library.

## Item manifests from the metadata CSV

The Jekyll plugin can write a manifest for every item of the site's metadata CSV (`metadata:` in
`_config.yml`), with no template. The images are found the way CollectionBuilder lists them, so the
CSV needs no new columns:

- an item with one image: its `object_location`
- a compound object: the `object_location` of each of its child rows (`parentid` = the item's
  `objectid`), in the order of the CSV. A child without a readable image is left out
- rows with a `parentid` are not items; rows with a `manifest` (an external one) are left alone;
  an item with no image of its own gets no manifest

Each image uses its level 0 folder if `rake generate_iiif` made one, and the image file otherwise.
Thumbnails come from `image_thumb`, with their size. A minimal setup for CollectionBuilder:

```yaml
static_iiif:
  manifests:
    v2: iiif/2/%{id}/manifest.json       # optional; version 3 is at iiif/3/%{id}/manifest.json
    language: en                         # of the field names; the records' own text is "none"
    summary: description
    rights: rightsstatement
    homepage: items/%{objectid}.html     # a path on the site, or a full URL
    provider: true                       # the site's title and url
    required_statement: [Rights, rights] # a label, and a column (or text)
    metadata_skip: [title, description, manifest]
    behavior: individuals                # or paged, continuous; or the name of a column
```

The other fields of `_data/config-metadata.csv` become the manifest's `metadata`, labelled with
their `display_name`. For a site built twice (another language, with its own `_config.en.yml`),
the second build writes its own manifests under its `baseurl`; set `language` (and a translated
`required_statement` label) in that config file. In the item layout, the `iiif_manifest` filter gives
the manifest's URL, for the viewer:

```liquid
{%- assign manifest_url = page.manifest -%}
{%- if manifest_url == nil or manifest_url == "" -%}{%- assign manifest_url = page.objectid | iiif_manifest -%}{%- endif -%}
```

Text on the images (annotations) goes in `iiif/annotations/<objectid>.csv` (the folder is the
`annotations` setting), one row per annotation, for the site's own images and for images elsewhere:

```csv
canvas,xywh,text,motivation
1,"706,1546,304,434",Person,
2,,The whole second image,tagging
```

`canvas` counts the item's images from 1, `xywh` is a region in the image's pixels (empty for the
whole image) and `motivation` defaults to `commenting`. They are written in version 3 only, as an
AnnotationPage embedded in the canvas's `annotations`.

A setting that names a column which the CSV does not have is read as text. A misspelled column
name then gives the same text for every item, so check one manifest after changing the settings.

## Manifests from data files

For a site whose images are served elsewhere (an existing IIIF server), the item manifests can be
built from plain files at build time instead of being exported once and committed. An item with
such a file uses it, whatever its other columns say. Per item:

```
iiif/canvases/<id>.csv   label,service,width,height[,format,profile]   one row per canvas, in order
iiif/toc/<id>.txt        a table of contents in the format above (optional)
```

`<id>` is the item's id in the metadata CSV (`objectid` in CollectionBuilder). Every row of that CSV with a
canvases file gets a manifest; the item's descriptive `metadata` comes from `_data/config-metadata.csv`
(`display_name` and `field`). In `_config.yml`:

```yaml
static_iiif:
  manifests:
    base_url: https://app.example.org      # the ids; default is url + baseurl; a path is put after url
    v3: iiif/3/%{id}/manifest.json         # output path(s); the first is the manifest id
    v2: ["iiif/2/%{id}/manifest", "iiif/2/%{id}/manifest.json"]   # optional
    canvases: iiif/canvases                # data directories (default shown)
    toc: iiif/toc
    label: title                           # a column of the metadata CSV, or text with %{column}
    viewing_direction: viewing_direction
    rights: rightsstatement
    summary: abstract
    homepage: https://app.example.org/items/%{objectid}.html
    thumbnail: image_thumb                 # default: the first canvas, 400 px wide
    required_statement: ["Attribution", "Example Library"]
    defaults: { viewing_direction: left-to-right, rights: "https://rightsstatements.org/vocab/CNE/1.0/" }
    service: { version: 2, profile: level1 }   # for canvases without a profile column
    metadata_skip: [manifest, manifest_v3]     # fields of config-metadata.csv to leave out
    pretty: false                              # true for indented JSON
    enabled: true                              # false: no manifests and no iiif_manifest links
    write: true                                # false: iiif_manifest gives the base_url ones, nothing written
```

A site built twice, once per interface language, should keep one URL per manifest. Let the first
build write them, and give the second build `base_url` (the first build's baseurl, e.g. `/demo`) and
`write: false`: its item pages then open the first build's manifests.

Keep `iiif/canvases` and `iiif/toc` out of the published site (`exclude:`). Manifests are written when
Jekyll writes the site and are not kept in memory; the ids use `base_url`, so a local build gives the
same ids as production. `StaticIIIF::DataManifests` does the same without Jekyll.

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

A working setup is in [cb-ja-demo](https://github.com/nakamura196/cb-ja-demo):
manifests at `/iiif/3/<objectid>/manifest.json` and `/iiif/2/<objectid>/manifest.json`
for one map (tiled) and one compound object, shown in Universal Viewer on the item page.
See `static_iiif:` in `_config.yml` and `_config.en.yml`, and `_layouts/item/iiif.html`.
CollectionBuilder's own files are not changed.

## Status

0.4: item manifests from the metadata CSV (the site's own images, or data files for images on
another server), tables of contents. 0.3: Image API 3 level 0 and Presentation 3; optionally Image
API 2 and Presentation 2 beside them; `behavior` (individuals / paged / continuous). Planned: a
collection manifest, TIFF sizes without libvips.

## Development

```sh
bundle install
bundle exec rake test   # the level 0 and Jekyll tests are skipped without libvips
```

## License

MIT
