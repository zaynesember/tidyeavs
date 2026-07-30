# data-raw

Scripts that build the datasets shipped in `data/`. Run each from the package
root, e.g. `Rscript data-raw/manifest.R`.

The curated metadata these read and write lives in `../metadata/`, shared with
any future Python implementation rather than kept inside this package. See
`../metadata/README.md`.

- `manifest.R` — builds `eavs_manifest`, the catalog of downloadable EAVS
  files. Downloads each file from eac.gov, records its byte size and SHA-256,
  and pins the current published version. Also derives `mirror_url` from
  `MIRROR_TAG`, checking that each release asset exists and leaving the column
  empty for any that does not, and writes `../metadata/manifest.csv`. Re-run
  when the EAC releases a revised version (update the version, release date, and
  URL first, and upload the new file to the mirror release). Source URLs were
  verified against eac.gov on 2026-07-18 and re-verified 2026-07-30.
- `dictionary.R` — builds `eavs_dictionary` from `../metadata/concepts.csv` and
  `../metadata/crosswalk.csv`, validating them first: it fails on an incomplete
  concept-year grid, a concept present in one file and not the other, a
  duplicate concept, or an unknown section or confidence value. No curated
  metadata lives in the script, so adding a concept or correcting a code means
  editing the CSVs.
- `jurisdictions.R` — builds `eavs_jurisdictions` from the raw files in the
  cache, downloading them if absent. Also writes
  `../metadata/jurisdictions.csv`. Its header comment is the authoritative fact
  list for jurisdiction quirks, and it asserts the exact published row count for
  each year.
- `schema.R` — writes `../metadata/schema.json`, the column types for the four
  metadata CSVs. Re-run after adding, removing, or retyping a column.
- `check_manifest.R` — verifies that the files the EAC publishes still match
  their pinned checksums. Run it every few weeks; a failure means the EAC
  released a revised version or moved a URL, and `manifest.R` needs updating. It
  checks `source_url` only, deliberately: see the header comment.

`sources/` is gitignored reference material, the EAC codebooks and the EPI
concept list. The crosswalk used to live there too, as an untracked
`crosswalk_candidate.csv`; it is now committed in `../metadata/` so it cannot be
lost and can be reviewed in a diff.
