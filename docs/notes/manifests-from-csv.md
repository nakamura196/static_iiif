# Item manifests from the metadata CSV — notes

## 2026-10-22 The site's own images, without a template

Goal: CollectionBuilder sites whose images sit in `objects/` (cb-ja-demo) should get their manifests
from the gem's `static_iiif: manifests:` settings, as sites with images on another server already do,
so that they stop changing CollectionBuilder's page generator (`cb_page_gen.rb`) and carry no
manifest templates of their own.

What was done:

- `DataManifests` takes the site's rows and a callable that describes a site path as an image.
  An item's canvases are its child rows' `object_location` (`parentid`), or its own. Rows with a
  `parentid` or a `manifest` are skipped. A canvases file, where there is one, wins.
- Small additions so that the output equals the former Liquid templates: a separate language for
  the item's own text (`value_language`, "none") and for field names (`language`); thumbnails with
  their size; `provider: true`; a homepage or thumbnail given as a site path gets `base_url` in front;
  HTML tags are taken out of the summary; `defaults: behavior`.
- Liquid filter `iiif_manifest` (item id → manifest URL, nil if none), for the item layout.

Measured:

- cb-ja-demo, built with Docker ruby:3.3 in both languages (`jekyll build`, then
  `--config _config.yml,_config.en.yml -d _site/en`), before (templates, static_iiif 8b097d9) and
  after (gem): the 8 manifests (2 items × v2/v3 × ja/en), compared as sorted JSON, are the same
  except that version 2 thumbnails now also carry `@type` and `format`. The item pages point at the
  same manifest URLs. The rest of `_site` differs only in the sitemap's `lastmod`.
- A site with images on another server, which uses the same gem with canvases files: rebuilt; all 4,434 manifest files
  are byte for byte the same as the build before the change.

Rejected:

- A new column listing an item's images (`a.jpg;b.jpg`), first proposed for nakamura196/lda, where one
  spread is shared by up to 20 articles. Dropped because it adds a convention CollectionBuilder users do
  not have; lda can use child rows (the same file in several child rows) and a one-time conversion
  instead.
- Taking images in four ways with an order of precedence. Reduced to CollectionBuilder's own two (one
  image, compound object) plus the existing canvases files for images elsewhere.

Found on the way:

- A setting that names a missing column is read as text. cb-ja-demo had `behavior: iiif_behavior`
  without such a column, so every manifest got the word "iiif_behavior", which is not a valid value, and
  `behavior` disappeared. Fixed in the config (`behavior: individuals`); the README warns about it.
- On macOS, the link from a level 0 folder to the original image was one `..` short when the folders
  were reached through a linked folder (`/var` → `/private/var`, the temporary folders the tests use).
  `Level0.link` now works from real paths. Two level 0 tests had failed on macOS for this reason.

Not checked: display in Mirador / Universal Viewer after the change (the manifests are the same as
before, which were checked on 2026-09-28).

## 2026-10-22 (later) Annotations from a data file; nakamura196/lda as the second site

What was done:

- `<annotations>/<id>.csv` (default `iiif/annotations`), one row per annotation: `canvas` (from 1),
  `text`, optional `xywh` and `motivation` (default `commenting`). Written in version 3 only, as an
  AnnotationPage embedded in the canvas's `annotations`. Works for both ways of finding images.
  Test `test_annotations` (58 tests pass, Ruby 4.0 from Homebrew).
- nakamura196/lda rebuilt as a CollectionBuilder site (worktree `lda.worktrees/collectionbuilder`):
  446 articles, 44 of them compound objects with 132 child rows; 178 spreads, one spread in up
  to 20 articles' child rows. The old site's 41 annotations (14 articles) went into 14 CSV files.

Measured:

- All 446 manifests generated at the old URLs. Compared with the old manifests (git 2780558):
  label, image URLs and sizes, canvas sizes, viewingDirection, thumbnail, rights and summary are the
  same for every item. Annotations: 41 before and after. Build time about 5 seconds.
- Universal Viewer 4.4.4 shows the plain JPEG bodies (no image service) when the page and the
  images are on the same site. Served from localhost with the images on github.io, the main image
  stayed black ("Error creating texture in WebGL"), the thumbnails showed.

Changed on the way:

- The old annotations had motivation `painting` with a TextualBody, which is not what painting is
  for; they are now `commenting`.
- Canvas ids changed from `.../manifest.json/canvas/p<n>` to `.../canvas/p<n>`; lda's curation.json
  files were rewritten to the new ids.

Not checked: whether UV 4 or Mirador draw the annotations; the curation files in IIIF Curation Viewer.
