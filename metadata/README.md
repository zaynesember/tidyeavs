# metadata

The curated metadata that every tidyeavs implementation reads. It lives here, at
the repo root, rather than inside `r/` so that the R package and any future
Python package build from the same files. A corrected variable code lands in one
place and both languages pick it up.

None of this is EAVS data. Raw survey files are never committed; they download on
demand into a local cache. What is here is the catalog of those files, the
crosswalk that maps their variable codes to stable concept names, and the
jurisdiction table.

## The files

Two are hand-edited and are the authoritative source for what they describe:

- **`concepts.csv`** — one row per concept: its `section` (`id`, or `A`–`F`), a
  plain-language `concept_label`, the MIT EPI's name for it where one exists, and
  `shipped`, which decides whether the concept reaches a built dictionary. A
  concept with `shipped = FALSE` stays curated here without being exported, which
  is how `poll_worker_difficulty` keeps its verified codes while its ordinal
  encoding is still being worked out.
- **`crosswalk.csv`** — one row per concept-year: the raw variable `code` that
  year, that year's `codebook_label` kept as provenance, a `confidence` rating,
  and any trap warning in `note`. A blank `code` means the item was not collected
  that year, which is different from an absent row and is why the file is a
  complete concept-year grid.

Two are generated and should not be hand-edited, since the next build overwrites
them:

- **`manifest.csv`** — written by `r/data-raw/manifest.R`. One row per
  downloadable file, pinning a published EAC version by SHA-256. `source_url` is
  where the EAC publishes it; `mirror_url` is a byte-identical copy on a GitHub
  release, which the packages try first so that an EAC re-release does not break
  installed copies. Both are checked against the same checksum, so it does not
  matter which one a download came from.
- **`jurisdictions.csv`** — written by `r/data-raw/jurisdictions.R`. Every
  published jurisdiction row per year, with the type and quirk flags that the
  script's header comment explains. It is generated, but it crosses the language
  boundary as data on purpose: the quirk logic is the part worth not
  reimplementing twice.

And one describes the rest:

- **`schema.json`** — the column types for all four CSVs, written by
  `r/data-raw/schema.R`.

## Read the string columns as strings

CSV carries no types and the defaults are not safe here. Use `schema.json` rather
than letting a reader guess. readr happens to guess correctly because a leading
zero makes a FIPS code look non-numeric, but pandas does not: a naive
`read_csv` turns Alaska's `0200000000` into the integer `200000000`, and every
`county_fips` becomes a float with the leading zero gone. In pandas, pass the
schema through as `dtype=`.

Variable codes have the same exposure. They are strings like `A1a` and `B18a`,
and while those will not parse as numbers, treating the whole file as text is the
habit that keeps the FIPS columns safe.

## Making changes

**Correcting a code, or adding a concept.** Edit `concepts.csv` and
`crosswalk.csv`, then rebuild the R dataset with `Rscript data-raw/dictionary.R`
from `r/`. That script validates what it reads before writing anything, so a
hand-edit that breaks the concept-year grid, references an unknown concept, or
uses an unrecognized section or confidence value fails there rather than
downstream. Verify each year's code against that year's codebook label; codes are
renumbered between cycles and are never safe to assume stable.

**Adding a survey year.** The year list is asserted in three places, by design:
`crosswalk.csv` needs a row per concept for the new year, `r/data-raw/manifest.R`
needs the new file's URLs, and `r/data-raw/jurisdictions.R` needs its published
row count. Rebuild all three datasets, re-run `Rscript data-raw/schema.R`, and
re-validate a cross-year series before trusting the result.
