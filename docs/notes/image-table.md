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
