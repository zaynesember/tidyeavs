# data-raw

Scripts that build the datasets shipped in `data/`. Run each from the package
root, e.g. `Rscript data-raw/manifest.R`.

- `manifest.R` — builds `eavs_manifest`, the catalog of downloadable EAVS
  files. Downloads each file from eac.gov, records its byte size and SHA-256,
  and pins the current published version. Re-run when the EAC releases a
  revised version (update the version, release date, and URL first). Source
  URLs were verified against eac.gov on 2026-07-18.
- `check_manifest.R` — verifies that the files published at the manifest's
  URLs still match their pinned checksums. CI runs it weekly
  (`.github/workflows/manifest-drift.yaml`); a failure means the EAC released
  a revised version or moved a URL, and `manifest.R` needs updating.
