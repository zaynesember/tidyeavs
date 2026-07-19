# tidyeavs — notes for Claude

A tidy R package for the U.S. Election Assistance Commission's Election
Administration and Voting Survey (EAVS). It downloads published EAVS files,
decodes their missing-value codes, and harmonizes variable names across survey
years so jurisdictions line up over time. Development happens on the `dev`
branch.

## Ground rules (read before writing anything)

- **Respect the data.** EAVS is the most comprehensive source on U.S. election
  administration. Never describe it—or the election officials who report it—as
  "bad data." It carries the gaps and inconsistencies any survey of thousands of
  independent jurisdictions would; document those honestly, mirror the EAC's own
  careful posture, and never imply the data or its reporters are at fault.
- **Corrections-free by design.** The package decodes missing codes and renames
  variables. It does **not** alter the values jurisdictions reported. Validation
  output is framed as *flags*, never *errors* or *corrections*.
- **No slop.** Keep writing concise and plain; no filler, no jargon to sound
  impressive, no manufactured enthusiasm. Before writing any prose (README,
  vignettes, roxygen), read the style guide at
  `/Users/zaynesember/Personal Git/writing-style` — `style-guide/core-voice.md`
  and `style-guide/work-docs.md`. Em-dashes are closed up (`word—word`);
  understatement over hype; avoid the usual AI tells.

## Current state

`R CMD check` passes clean (0 errors / 0 warnings / 0 notes). Verified end to end
against the published record (row counts per year, mail-rejection rates ~0.8–1.5%,
UOCAVA rejection, drop boxes appearing only 2022+).

Exported API (two tiers):

- One-shot: `eavs_load(years)` → download + decode + harmonize into a tidy
  jurisdiction-year panel.
- Steps: `eavs_download()`, `eavs_read()`, `eavs_recode_missing()`,
  `eavs_missing_status()`, `eavs_harmonize()`, `eavs_items()`.
- Cache: `eavs_cache_dir()`, `eavs_cache_list()`, `eavs_cache_clear()`.

Shipped datasets: `eavs_manifest` (file catalog), `eavs_dictionary` (the
cross-year crosswalk), and `eavs_jurisdictions` (per-year jurisdiction rows
with quirk flags).

**No GitHub Actions** — decided 2026-07-19; don't re-add workflows. The repo
is private and Actions runs never start (billing-gated). Checks run locally
instead: `devtools::check()` before committing, and
`Rscript data-raw/check_manifest.R` every few weeks — it re-downloads every
manifest URL and fails on checksum mismatch, i.e. the alarm for EAC
re-releases.

Done: scaffold, cache/download, read, recode, manifest, dictionary, harmonize,
items, load, jurisdictions, unit tests, README, manifest drift script.
Remaining (approach notes below): `eavs_aggregate`, `eavs_flags`, integration
tests vs published EAC report totals, vignettes, and the GitHub-releases data
mirror.

## How it fits together

`R/` (one concern per file):

- `cache.R` — cache directory resolution and helpers. Location precedence:
  option `tidyeavs.cache_dir` → env `TIDYEAVS_CACHE_DIR` →
  `tools::R_user_dir("tidyeavs", "cache")`.
- `download.R` — `eavs_download()`; looks a file up in `eavs_manifest`, fetches
  mirror-first then eac.gov, verifies SHA-256, reuses a cached copy if it matches.
- `read.R` — `eavs_read()`; reads one year **all-character** (so FIPS leading
  zeros and sentinel codes survive), handling zipped vs plain CSV and encoding
  (see gotchas).
- `recode.R` — `eavs_recode_missing()` / `eavs_missing_status()`; detects numeric
  item columns and maps sentinels to `NA` while preserving the reason.
- `dictionary.R` — `eavs_items()` search + internal dictionary resolution.
- `harmonize.R` — `eavs_harmonize()`; renames a year's raw codes to concept names
  using the dictionary.
- `load.R` — `eavs_load()`; the composition of the above, bound across years.
- `data.R` — dataset roxygen docs. `globals.R`, `utils.R` — helpers.

`eavs_harmonize()` and `eavs_items()` take an optional `dictionary=` argument
(defaults to the bundled one), which is how the unit tests exercise them without
the shipped data.

## Data model

**`eavs_manifest`** — one row per downloadable file. Columns: `survey`
(`eavs`/`policy`), `year`, `format` (`csv`/`xlsx`), `version`, `release_date`,
`file_name`, `bytes`, `sha256`, `source_url`, `mirror_url`. Covers EAVS and
Policy Survey, 2016–2024. Each row pins one EAC version by checksum.
`mirror_url` is `NA` for now (downloads come from eac.gov); the plan is to mirror
the exact files as GitHub release assets and fill this in — the download code
already prefers the mirror and falls back to eac.gov.

**`eavs_dictionary`** — the cross-year crosswalk, one row per concept per year.
Columns: `concept` (stable snake_case), `concept_label`, `section` (`A`–`F`, or
`id`), `year`, `code` (raw variable that year, or `NA` if not collected),
`codebook_label` (that year's label, kept as provenance), `epi_name` (the MIT
EPI's name), `note` (caveats, especially trap warnings), `confidence`
(`high`/`medium`/`low`). Curated: 39 concepts spanning registration, mail,
UOCAVA, provisional, participation, polling places, drop boxes, and curing —
**not** all ~400 columns. EAVS only for now; the Policy Survey isn't in the
dictionary yet.

Raw EAVS data is never committed — it downloads on demand into the cache.

## The hard parts (EAVS facts — don't re-derive these)

- **Missing-value sentinels changed regime.** 2018+: `-88` "does not apply",
  `-99` "data not available", `-77` "valid skip" (added 2020). 2016 and earlier:
  `-888888` / `-999999` (plus stray `-999998`/`-999991`). Because every EAVS item
  is a count or rate, the recoder treats any negative in an item column as
  missing (known codes get their specific status; others → `other_missing`).
- **Cross-year renumbering is the core hazard.** The same code can mean different
  things in different years. Canonical trap: `B18a` = "UOCAVA counted" in 2024 but
  "UOCAVA rejected" in 2018–2022. Also: mail counted/rejected moved `C3a/C4a` →
  `C8a/C9a` at the **2020→2022** break (drop-box questions were inserted then, not
  2022→2024); registrations-rejected is `A3e` in 2018–2022 but `A3f` in 2024
  (Section A was redesigned). The dictionary encodes the correct code per year;
  the `note` column spells out each trap. When adding concepts, verify every
  year's code against that year's codebook label — never assume a code is stable.
- **Encoding.** EAVS CSVs are usually Windows-1252 (Excel/SPSS exports), which
  breaks a naive UTF-8 read on names like "Doña Ana." `read.R:file_encoding()`
  detects UTF-8 vs Windows-1252 per file.
- **2016 sentinel format.** 2016 writes sentinels as `"CODE: Label"` (e.g.
  `"-999999: Data Not Available"`) rather than a bare number.
  `utils.R:strip_code_label()` reduces these to the code before recoding.
- **Jurisdiction quirks** — now encoded in `eavs_jurisdictions` (built by
  `data-raw/jurisdictions.R`, whose header comment is the authoritative fact
  list). The short version, verified against the published files: `FIPSCode`
  is a *string* of varying length. Wisconsin uses ~1,850 five-digit
  non-geographic serials (county only in the name; town/village pairs share a
  serial in 2020 [82575, 84275] and 2022 [31550] — real duplicate codes in the
  published files). Maine files a statewide UOCAVA pseudo-row (`"23."` in
  2016, `"23"` later) and codes five townships to a `"099"` county bucket —
  but `099` is a *real* county code in other states (Macomb MI, Stanislaus
  CA), so never exclude it globally. Alaska and the territories are one
  `SS00000000` row each (AS/MP join in 2020; PR skips midterms). DC is
  `1100100000`. Kalawao HI appears every year but Maui administers it.
  Illinois city election boards (Aurora 2016 only; Bloomington, Danville,
  East St. Louis, Galesburg all years) are **place-coded** (`17`+place+`000`),
  so their middle digits are not a county. Sub-county codes in
  CT/MA/ME/NH/RI/VT do embed real county FIPS (CT's are pre-2022 Census
  counties). 2024 Alameda/Calaveras CA lost a leading zero (9 digits). NY 2016
  codes Yates County `3612295082` (malformed; `3612300000` from 2018). SD's
  Oglala Lakota is `4611300000` in 2016, `4610200000` after. Exact published
  row counts: 6467 / 6460 / 6460 / 6460 / 6461 for 2016–2024. 2016 identifier
  columns differ (`JurisdictionName`, `State`, `FIPS_2Digit`) from 2018+
  (`Jurisdiction_Name`, `State_Full`, `State_Abbr`) — the dictionary's `id`
  rows handle this.
- **`poll_worker_difficulty` is deferred.** It's an ordinal stored as text labels
  in 2016/2018 but numeric codes later; harmonizing it needs care. It's excluded
  from the shipped dictionary but kept in the source crosswalk for later.
- **EAC re-releases revised versions** of a cycle for years afterward (quarterly
  errata). The manifest pins a version by checksum; when a new version drops,
  update `version`/`release_date`/`source_url` and re-run the build.
- **eac.gov URLs churn** across three CMS generations, and `/media/NNNNNN` links
  are HTML landing pages, not files. Keep a per-file manifest; don't compute URLs.

## Rebuilding the shipped data

Source material (codebooks, the crosswalk candidate) lives in
`data-raw/sources/`, which is **gitignored** — re-download via the scripts if
absent.

- `Rscript data-raw/manifest.R` — downloads every file, computes byte size + SHA,
  writes `data/eavs_manifest.rda`. URLs verified 2026-07-18.
- `Rscript data-raw/dictionary.R` — reads `data-raw/sources/crosswalk_candidate.csv`
  (the verified cross-year codes) plus curated concept metadata, writes
  `data/eavs_dictionary.rda`.

- `Rscript data-raw/jurisdictions.R` — reads the raw files from the cache
  (downloading if absent), writes `data/eavs_jurisdictions.rda`. Its header
  comment is the fact list for jurisdiction quirks; it asserts exact published
  row counts per year.
- `Rscript data-raw/check_manifest.R` — verifies the published files still
  match the manifest checksums (the weekly CI drift check runs this).

**Adding a survey year:** add its rows to `data-raw/manifest.R` (verify the URLs
first), then extend the crosswalk — for each concept, look up the new year's code
by matching the codebook label, and record traps in `note`. Extend
`data-raw/jurisdictions.R` too: add the new year's published row count to the
assertion and check the new file for fresh quirks (shared codes, dropped
zeros, new territories). Then rebuild the datasets and re-validate a
cross-year series.

## Dev workflow

```r
devtools::load_all()
devtools::document()          # regenerate NAMESPACE + man/ after roxygen changes
testthat::test_local()        # unit tests (offline; fixtures, no network)
devtools::check(vignettes = FALSE)
```

Unit tests are network-free (they use fixture dictionaries and the bundled
manifest). Real-data checks are run manually against live downloads; turning the
"replicate published EAC report totals" check into an integration test is a
tracked task.

Reference implementation for the pending data work (rate formulas,
QA/consistency checks): MIT's Elections Performance Index pipeline at
`/Users/zaynesember/MIT Git/2024-epi` — mine it for approaches, but keep
tidyeavs corrections-free (the EPI *corrects* — e.g. it drops Kalawao and
zeroes Maine's statewide row; tidyeavs *flags* the same rows).

## Remaining work

- **`eavs_aggregate`** — quirk-aware rollups to state (or county), handling the
  Maine statewide row, Wisconsin codes, and territory exclusion, with loud
  row-count assertions. Decide the API shape. `eavs_jurisdictions` now carries
  the per-row type/flags this needs; join on `year` + `fips_code` (beware the
  three shared WI codes — `shared_code` marks them).
- **`eavs_flags`** — a tidy table of internal-consistency flags (subparts exceed
  a total, returned > transmitted, extreme year-over-year swings). Flags, never
  mutations.
- **Integration tests** vs published EAC report totals.
- **Vignettes** — getting started; survey structure and what changed when;
  missingness; comparing across years safely.
- **Data mirror** — upload the exact EAC files to GitHub releases and populate
  `mirror_url` in the manifest.
