# Two parts in the README, and canvases from a table of images — notes

## 2026-10-24 Design (nothing implemented yet)

### Why

The gem does two separate jobs, and the README mixes them:

- **Manifests** — what Omeka S's IIIF Server module does. Needs only the image URLs and sizes.
- **Images** (level 0 sizes and tiles) — what Omeka S's Image Server module does. Needs libvips and
  local image files.

Most sites that want IIIF manifests already have their images on an IIIF server (a library's, NDL's,
an institution's Cantaloupe). For them the image part is irrelevant, yet the README opens with it.
The one gem stays one gem; only the README is reorganized, with the "images elsewhere" case first.

The second gap: for images elsewhere, the canvases files (`iiif/canvases/<id>.csv`:
label, service, width, height) need each image's size. The one site using them so far got its sizes
from an Omeka export. A new site has only a list of info.json URLs, and someone has to read each
info.json once. That is the tool below.

### README (part 1: manifests, part 2: images)

1. Opening: one gem, two parts, either can be used alone. One sentence each on the Omeka S
   equivalents (IIIF Server / Image Server).
2. **Part 1, Manifests**
   1. Images on another IIIF server: the image table → `static-iiif canvases` → `iiif/canvases/` →
      manifests at build time (the current "Manifests from data files", plus tables of contents and
      annotations).
   2. Images in the site itself: item manifests from the metadata CSV (current section, unchanged).
   3. The Ruby builder (current "Ruby").
3. **Part 2, Images**: the `generate` command, level 0, tiles, version 2, the UV thumbnail sizes
   (moved down from the opening).
4. Shared: Jekyll, Rake, CollectionBuilder, Status, Development.

Text is moved, not rewritten, except the opening and the short lead of each part.

### The tool: `static-iiif canvases TABLE... [--out iiif/canvases]`

Input, one or more CSV files (e.g. one per batch or per collection):

```
objectid,info,label
doc001,https://images.example.org/iiif/2/doc001_0001/info.json,表紙
doc001,https://images.example.org/iiif/2/doc001_0002/info.json,1
doc002,https://images.example.org/iiif/3/x9/info.json,
```

- `objectid`: the item (`--id-column` to name another). `info`: the info.json URL; a service URL
  without `/info.json` is accepted too. `label`: optional. Other columns are ignored, so an existing
  spreadsheet can be used as it is.
- Canvas order = row order; files are read in the order given. An item whose rows are spread over
  several files is allowed and keeps that order.

Output: `<out>/<objectid>.csv` per item, `label,service,width,height,profile,version`.

Decisions:

- **Each info.json is read once.** Before fetching, the tool reads the existing canvases files and
  reuses width/height for any service URL already there. A second run after adding 10 images fetches
  10. `--refresh` reads everything again. No separate cache file: the canvases files are the record.
- **Not at build time.** Run by hand, once, like `generate`. A Jekyll build that fetches 100,000
  info.json files would be slow, depend on someone else's server, and give a different site when that
  server is down.
- **A `version` column** is added to the canvases file (optional; the gem reads it, falling back to
  the site's `service: version:` as now). Today the version is one setting for the whole site, but one
  table can mix servers (version 2 and 3). The tool takes the version from the info.json (`@context`)
  and the profile from `profile` (version 2: the first entry, a URI, shortened to `level1` etc.).
- **The given URL wins over the info.json's own id.** Servers often report `http://` or an internal
  host name. When they differ, the tool warns and uses what the table says.
- **Failures do not leave half an item.** An item with any failed row is not written; the failures are
  listed at the end and the exit status is 1. Running again fetches only what is still missing.
- **Files are written only when their content changes**, so git shows only real changes. Items that are
  in `<out>` but not in any table are left alone (counted in the summary, not deleted).
- Fetching: Ruby's standard library only (no new dependency), 4 at a time (`--jobs`), a timeout,
  up to 3 retries with a pause, at most 3 redirects, User-Agent `static_iiif/<version>`.
- Tests: the fetcher is passed in, so tests use fixture info.json files (version 2 and 3) and no network.

Rejected:

- Reading sizes at build time (above).
- Splitting into two gems (manifests / images). Decided against: they share the URL scheme, the
  Jekyll plugin and the configuration; the split is made in the README instead.
- Image URLs in a column of the metadata CSV (rejected already on 2026-10-22 in
  `manifests-from-csv.md`); the image table is a separate file, and the canvases files stay what the
  build reads.
- A separate cache of fetched sizes. It would be a second copy of what the canvases files already hold.

Estimate to check: the largest existing site has 118,384 canvases. At about 50 ms per request with 4
in parallel, a first run would take about 25 minutes; reruns take seconds.

Not decided: whether a Rake task (`static_iiif:canvases`) is worth adding beside the command.

## 2026-10-24 (later) Correction: images elsewhere in `object_location`; four example sites

### Correction to the design above

The image table above is a new file with its own columns. CollectionBuilder users know one file, the
metadata CSV: one row per item, the image in `object_location`, several images as child rows
(`parentid`). The same rule was applied to lda on 2026-10-22 (`manifests-from-csv.md`). So:

- **The basic way for images on another IIIF server:** write the info.json URL in `object_location`
  (one image), or in each child row's `object_location` (several). The only thing a user learns is
  "an info.json URL instead of an image URL". `image_small` / `image_thumb` can hold IIIF image URLs as
  CollectionBuilder already allows.
- The gem treats an `object_location` ending in `/info.json` as an image on an IIIF server. Today it
  ignores external URLs (4 of 15 items in cb-theme-test).
- The size-reading tool reads those URLs from the metadata CSV, each info.json once, and keeps the
  sizes in a file the build reads (`service,width,height,profile,version`). Users do not edit it.
  Still not at build time, and still with the rules above (retry, nothing half-written, writes only
  on change).
- **The canvases files stay, as a second way**, mentioned in two or three lines of the README with a
  link to their format: for many canvases (the largest site using them has 118,384, which as child rows
  would be a metadata CSV nobody can open), for tables of contents (child rows cannot express them),
  and for migration from another system. The site is described by its size only, not by name.
- The tool also fills canvases files from an image table, for that second way. Whether this is worth
  keeping is decided after the first way works.

Not checked yet: how the rest of CollectionBuilder (download button, browse thumbnails, item page
image) behaves when `object_location` is an info.json URL. Check in a test site before implementing.

### Example sites, one per way

| way | site |
|---|---|
| no IIIF (CollectionBuilder as it is) | CollectionBuilder's own demo |
| images on another IIIF server, basic way | cb-ja-demo |
| local images, manifests only | the paper database (5,444 microscope images) |
| local images, level 0 sizes and tiles | nakamura196/lda |
| canvases files (large sites, migration) | mentioned only |

- **cb-ja-demo:** 58 of its 69 items use manifests from the University of Tokyo Digital Archive
  (the `manifest` column, CollectionBuilder's own way). Turn a few of them into `object_location` =
  info.json and keep the rest, so that both ways sit side by side; 10 items already have local tiles.
  The walkthrough uses cb-ja-demo's data, so it can show all three. Caveat for the text: this archive
  publishes its own manifests, so the reason to use info.json here is to describe the item yourself
  (titles and summaries in Japanese and English, images from several manifests in one item).
  The archive refuses some requests from localhost (note in `head.html`); the tool fetches outside the
  browser, so this should not matter, but whether viewers load the info.json is checked after publishing.
- **Paper database:** all 5,444 images are 1440×1080, so tiles add nothing; the typical "manifests
  only" case. The CollectionBuilder conversion (350 observation points as parents, images as child rows)
  was prototyped on 2026-10-22; it now links to the old version 2 manifests. Switch to manifests made by
  the gem from the child rows. Constraints: 0.97 GB of originals, so not GitHub Pages (published to
  its own server with rsync); the prototype is not pushed and some questions are open.
- **lda:** its 188 spreads are all 3,680 px on the long side, under the default tile threshold
  (4,000 px), so the defaults would make sizes but no tiles. Lower the threshold (e.g. 2,000 px) to tile
  all of them; magazine spreads with small type are a fair reason for deep zoom. Expected size: tiles
  about as large as the originals (cb-theme-test: 26 MB of images, 28 MB of tiles), so the site goes
  from 233 MB to roughly 400 MB, under the 1 GB Pages limit.

Rejected:

- One new demo site per way with the same images. Existing sites already cover each way with real
  data; a new site would be one more to maintain.
- Using the largest canvases-files site as the example for images elsewhere. It uses the second way,
  not the one CollectionBuilder users would write.

Order of work (each a separate session): README in two parts → `object_location` = info.json in the gem
and the tool, tried on cb-ja-demo → lda tiles → paper database.

## 2026-10-24 (later) README in two parts, done (not committed)

Sections moved, not rewritten: opening (two parts, which you need), Part 1 (images on another IIIF server
first, then images in the site, own templates, Ruby), Part 2 (level 0, command, version 2, Rake, info.json
at build time), then Jekyll, CollectionBuilder, Status. Checked by diffing the sorted lines of the old and
new README: what disappeared is the old opening's bullets and re-wrapped lines. The "images on another
server" section still describes the canvases files; it changes when `object_location` = info.json is built.

## 2026-10-24 (later) Found: the size-reading tool already exists in one site

The largest site using canvases files already has an ingest script (Python, written in another session
and merged there): staff upload tables of canvases with image URLs, and the script reads each new
info.json, reuses the sizes already in `iiif/canvases/`, and reports images whose size could not be read.
Its staff manual is written around that. So the tool in the gem is a port of something already in use,
not a new idea; port its rules (reuse, report per row) rather than designing them again. That site's
procedures do not change with today's decisions.

## 2026-10-24 (later) Checked: how the rest of CollectionBuilder behaves with an info.json in `object_location`

Tried in cb-ja-demo, worktree `cb-ja-demo.worktrees/info-json` (branch `info-json`, not committed).
One item, `jitsu_8edec05c` (1 image): `manifest` emptied, `object_location` =
`https://iiif.dl.itc.u-tokyo.ac.jp/iiif/jitsuroku/images/01010001.tif/info.json`, `image_small` /
`image_thumb` left as IIIF image URLs. Built with the gem at the site's pinned ref (no change to the gem
yet), once with `display_template: iiif` (the site's own layout), once with `image` (CollectionBuilder's).

- **Manifest:** the gem writes `iiif/3/jitsu_8edec05c/manifest.json` with 0 canvases, as expected: the
  `iiif_image` filter skips external URLs. This is the part to implement.
- **`iiif` layout (cb-ja-demo's own):** has no download button and no item thumbnail, so the info.json
  URL appears nowhere on the item page. Universal Viewer gets the gem's manifest.
- **`image` layout (CollectionBuilder's default):** `image_small` shows correctly. Two things break:
  - "Click to view full screen" (Spotlight gallery) opens `object_location` as an image: a broken-image
    icon, checked in Chrome.
  - The download button reads "ダウンロード JPEG" and links to the info.json (a JSON text).
- **Browse cards:** use `image_thumb` only. Unaffected while `image_thumb` is filled; with it empty, the
  card has no image.
- **Data downloads** (`assets/data/metadata.json` / `.csv`): `object_location` is the info.json URL.
- Not built, read from the templates: the featured image / jumbotron of an `image` item and
  `feature/image-comparison` take `object_location` before `image_small` (would break the same way);
  compound objects' child gallery and download menu use each child's `object_location` (same as above);
  `og:image` and the timeline take `image_small` first (fine).
- **The info.json's own id differs from the given URL:** `@id` is
  `https://iiif.dl.itc.u-tokyo.ac.jp/iiif/2/jitsuroku%2Fimages%2F01010001.tif` (path `iiif/2/`, slashes
  encoded), the URL in the table is `iiif/jitsuroku/images/01010001.tif`. The "given URL wins" rule above
  has a real case. Version 2, `level2`, 5732×4046.

So with CollectionBuilder's own templates, an info.json in `object_location` works only where
`object_location` is not used as an image file (the `iiif`-style layout). Everywhere CollectionBuilder
uses it as "the image file", it breaks.

## 2026-10-24 (later) Built: info.json in `object_location` (not committed)

Decided (with the user): **the plugin rewrites those rows at build time**, so CollectionBuilder's own
templates need no change. Rejected: limiting info.json items to an `iiif`-style layout (CollectionBuilder
has no such layout, so the gem or a theme would have to ship one, and there would be no download button).
Cost of the choice: the value a user wrote is not the value templates see; documented in the README.

What was made:

- `StaticIIIF::Services` (`lib/static_iiif/services.rb`): one sizes file, `iiif/services.csv`
  (`service,width,height,profile,version`), for the whole site, not one file per item as in the design
  above. "Nothing half-written" moved to the build: an item with an image whose size is unknown gets no
  manifest, and the build warns once with the count and the first one.
- `static-iiif sizes [CSV...]`: reads `_data/<metadata>.csv` from `_config.yml` by default; reuses known
  sizes, `--refresh`, `--jobs` (4), `--column`, `--out`; standard library only (Net::HTTP, 30 s timeout,
  3 tries with a growing pause, 3 redirects, User-Agent `static_iiif/<version>`); exit 1 on failures;
  writes only on change; notes when the info.json's id differs.
- Jekyll `:site, :post_read` hook: `object_location` → `full/max` (version 3) or `full/full` (version 2,
  also when the size is not read yet), empty `image_small` / `image_thumb` → `800,` / `400,` (widths, as
  the ingest script uses; supported by level 1), original kept in `static_iiif_info`.
- `DataManifests` takes `services:` and makes canvases with the given URL as the service.
- Not done: the `iiif_image` Liquid filter (sites with their own manifest templates) still ignores
  external URLs; the tool that fills canvases files from an image table; a Rake task.

Checked:

- Tests: 68 runs, 0 failures (7 new in `test/test_services.rb`, fetcher passed in, no network).
- cb-ja-demo, worktree `info-json`, now on top of branch `gem-manifests` (the site's manifests come from the
  gem there), `Gemfile` pointing at this worktree by `path:` (trial only). Same item `jitsu_8edec05c`.
  Build before `sizes`: the warning, no manifest. `static-iiif sizes`: read 1, wrote the file; second run
  "No change". Build after: v3 and v2 manifests with 1 canvas, 5732×4046, service = the URL in the metadata.
  In Chrome: Universal Viewer shows the page (`iiif` layout); with the `image` layout the full screen view
  loads the image (5732 px wide) and the download button links to `full/full/0/default.jpg`.
- Not checked: an item with child rows; a version 3 server; the browse card with an empty `image_thumb`
  (unit test only); the English build (`_config.en.yml`, `write: false`).

## 2026-10-24 (later) Checked: an item with child rows

cb-ja-demo, worktree `info-json`, same setup as above. `jitsu_6d9db582` made a compound object:
`manifest` and `object_location` emptied, `display_template: compound_object`; three child rows
`jitsu_6d9db582_001`–`003` with only `object_location` = the info.json of pages 01010064–66 (no
`image_small` / `image_thumb`), `display_template: image`.

- Build before `sizes`: warned "no manifest for 1 item(s): the size of 3 image(s) … First: jitsu_6d9db582";
  no manifest written.
- `static-iiif sizes`: "Read 3, already known 1, failed 0"; each info.json again calls itself
  `iiif/2/jitsuroku%2Fimages%2F…` (noted, the metadata URL kept).
- Build after: v3 and v2 manifests with 3 canvases in child order, labels from the child titles,
  5732×4046 each, service = the URL in the metadata, body `full/full` (version 2 server).
- Item page (CollectionBuilder's `compound_object` layout), in Chrome: the three child thumbnails
  (`400,`) and medium images (`800,`) load; "full screen" and "download JPEG" for each child, and the
  item's download menu, link to `full/full/0/default.jpg` (200, image/jpeg). No info.json URL left on the page.
- `assets/data/metadata.csv`: the child rows' `object_location` is the rewritten `full/full` URL.
- The CSV is CRLF; rewriting it with Python's csv module turned every line into LF (all rows in the diff).
  Write with `\r\n` or fix afterwards.
- Still not checked: a version 3 server; the English build.

## 2026-10-24 (later) Checked: the English build

cb-ja-demo, worktree `info-json`, same two items as above. Built the Japanese site to `_site`, then
`jekyll build --config _config.yml,_config.en.yml -d _site/en` (`static_iiif.manifests.write: false`,
`base_url: /cb-ja-demo`). Homebrew Ruby needed: the system Ruby's bundler is too old for the lockfile.

- No warning in the English build: `iiif/services.csv` is read the same way, so both items count as known.
- No manifests written under `_site/en/iiif/`, as configured. `en/items/jitsu_8edec05c.html` gives
  Universal Viewer, the IIIF button and Mirador the Japanese build's
  `/cb-ja-demo/iiif/3/jitsu_8edec05c/manifest.json` (1 canvas, written there).
- `en/items/jitsu_6d9db582.html` (compound object): the same `400,` / `800,` / `full/full` URLs for the three
  children as the Japanese page. No info.json URL in any page or data file of either build.
- `en/assets/data/metadata.csv`: `object_location` of these rows equals the Japanese one (rewritten).
- Found: `iiif/services.csv` is copied into the output, as `_site/iiif/services.csv` and
  `_site/en/iiif/services.csv` (5 lines here). Harmless (sizes of public images), but not meant to be
  published; a site can add it to `exclude`, or the gem could default to a path Jekyll skips (`_` prefix).
  Not decided.
- Still not checked: a version 3 server.

## 2026-10-25 Decided: the sizes file moves to `_iiif/services.csv`

The default of `static_iiif: services:` and of `static-iiif sizes --out` is now `_iiif/services.csv`.
Jekyll does not copy folders whose names start with `_`, so the file stays out of `_site` without an
`exclude:` entry in every site. Rejected: keeping `iiif/services.csv` and telling sites to exclude it (one
more line each site has to remember, and the English build copied it too). README, the command's help and
the test's path changed with it; tests 68 runs, 0 failures (Homebrew Ruby). Sites made with the old default
(cb-ja-demo worktree `info-json`) need the file moved, or `services:` set.
