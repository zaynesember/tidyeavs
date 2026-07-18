# data-raw

Scripts that build the datasets shipped in `data/`. Run each from the package
root, e.g. `Rscript data-raw/manifest.R`.

- `manifest.R` — builds `eavs_manifest`, the catalog of downloadable EAVS
  files. Downloads each file from eac.gov, records its byte size and SHA-256,
  and pins the current published version. Re-run when the EAC releases a
  revised version (update the version, release date, and URL first). Source
  URLs were verified against eac.gov on 2026-07-18.
